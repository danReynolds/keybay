import 'dart:convert';
import 'dart:io';
import 'package:keybay_cli/src/failure.dart';
import 'dart:typed_data';

import 'package:keybay_cli/src/process_executor.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('keybay-resolve-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  File executable(String name, {bool executable = true}) {
    final file = File('${directory.path}/$name');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('fixture');
    expect(
      Process.runSync('chmod', [
        executable ? '700' : '600',
        file.path,
      ]).exitCode,
      0,
    );
    return file;
  }

  PosixCommandExecutor resolver(_FakeExecveSystem system) =>
      PosixCommandExecutor(
        system: system,
        stderr: StringBuffer(),
        workingDirectory: directory.path,
      );

  test(
    'empty/relative PATH entries use captured cwd; canonical argv is frozen',
    () async {
      final target = executable('bin/tool');
      Link('${directory.path}/tool').createSync(target.path);
      final system = _FakeExecveSystem({});
      final executor = resolver(system);
      final args = ['arg'];
      final command = executor.prepare(
        executable: 'tool',
        arguments: args,
        environment: {'PATH': ':not-used'},
      );
      args[0] = 'changed';
      expect(command.path, target.resolveSymbolicLinksSync());
      expect(command.arguments, ['tool', 'arg']);
      expect(system.calls, isEmpty);
      expect(
        await executor.execute(command: command, overlay: {'PATH': '/hostile'}),
        126,
      );
      expect(system.calls.single.path, command.path);
      expect(system.calls.single.arguments, ['tool', 'arg']);
      expect(system.calls.single.overlay, {'PATH': '/hostile'});
    },
  );

  test('unset PATH never searches, empty PATH searches cwd', () {
    final target = executable('tool');
    final executor = resolver(_FakeExecveSystem({}));
    expect(
      () =>
          executor.prepare(executable: 'tool', arguments: [], environment: {}),
      throwsA(isA<CliFailure>().having((e) => e.exitCode, 'status', 127)),
    );
    expect(
      executor
          .prepare(executable: 'tool', arguments: [], environment: {'PATH': ''})
          .path,
      target.resolveSymbolicLinksSync(),
    );
  });

  test('relative and absolute commands bypass PATH', () {
    final target = executable('bin/tool');
    final executor = resolver(_FakeExecveSystem({}));
    for (final name in ['./bin/tool', target.path]) {
      final command = executor.prepare(
        executable: name,
        arguments: [],
        environment: {'PATH': '/absent'},
      );
      expect(command.path, target.resolveSymbolicLinksSync());
      expect(command.arguments, [name]);
    }
  });

  test(
    'search continues past unusable candidates; unusable wins over absent',
    () {
      executable('one/tool', executable: false);
      Directory('${directory.path}/two/tool').createSync(recursive: true);
      final target = executable('three/tool');
      final executor = resolver(_FakeExecveSystem({}));
      expect(
        executor
            .prepare(
              executable: 'tool',
              arguments: [],
              environment: {'PATH': 'one:two:three'},
            )
            .path,
        target.resolveSymbolicLinksSync(),
      );
      expect(
        () => executor.prepare(
          executable: 'tool',
          arguments: [],
          environment: {'PATH': 'one:two:absent'},
        ),
        throwsA(isA<CliFailure>().having((e) => e.exitCode, 'status', 126)),
      );
      Link('${directory.path}/dangling').createSync('missing');
      expect(
        () => executor.prepare(
          executable: './dangling',
          arguments: [],
          environment: {},
        ),
        throwsA(isA<CliFailure>().having((e) => e.exitCode, 'status', 127)),
      );
    },
  );

  test(
    'every execution failure makes exactly one attempt, with no fallback',
    () async {
      final target = executable('tool');
      for (final errno in [2, 8, 13, 20, 5]) {
        final system = _FakeExecveSystem({
          target.resolveSymbolicLinksSync(): errno,
        });
        final executor = resolver(system);
        final command = executor.prepare(
          executable: 'tool',
          arguments: [],
          environment: {'PATH': ''},
        );
        expect(await executor.execute(command: command, overlay: {}), 126);
        expect(system.calls, hasLength(1));
      }
    },
  );

  group('overlayShadowsEnvEntry (raw environ passthrough)', () {
    List<Uint8List> names(List<String> values) => <Uint8List>[
      for (final value in values) utf8.encode(value),
    ];

    Uint8List entry(List<int> bytes) => Uint8List.fromList(bytes);

    test('matches exactly the overlaid name, not prefixes or suffixes', () {
      final overlay = names(<String>['INJECTED']);
      expect(
        overlayShadowsEnvEntry(utf8.encode('INJECTED=old'), overlay),
        isTrue,
      );
      expect(overlayShadowsEnvEntry(utf8.encode('INJECTED='), overlay), isTrue);
      expect(
        overlayShadowsEnvEntry(utf8.encode('INJECTED_2=x'), overlay),
        isFalse,
      );
      expect(overlayShadowsEnvEntry(utf8.encode('INJECT=x'), overlay), isFalse);
      expect(overlayShadowsEnvEntry(utf8.encode('OTHER=x'), overlay), isFalse);
    });

    test('a non-UTF-8 parent value cannot hide a shadowed name', () {
      // NAME=<0xff> — the value bytes are irrelevant to the name match.
      final raw = entry(<int>[...utf8.encode('INJECTED='), 0xff]);
      expect(overlayShadowsEnvEntry(raw, names(<String>['INJECTED'])), isTrue);
    });

    test('a non-UTF-8 parent NAME never matches an overlay name', () {
      final raw = entry(<int>[0xff, 0x3d, 0x78]); // <0xff>=x
      expect(overlayShadowsEnvEntry(raw, names(<String>['X'])), isFalse);
    });

    test('an entry without = passes through even when it equals a name', () {
      expect(
        overlayShadowsEnvEntry(utf8.encode('INJECTED'), names(['INJECTED'])),
        isFalse,
      );
      expect(
        overlayShadowsEnvEntry(entry(const <int>[]), names(['X'])),
        isFalse,
      );
    });
  });
}

final class _ExecveCall {
  _ExecveCall({
    required this.path,
    required List<String> arguments,
    required Map<String, String> overlay,
  }) : arguments = List<String>.of(arguments),
       overlay = Map<String, String>.of(overlay);

  final String path;
  final List<String> arguments;
  final Map<String, String> overlay;
}

final class _FakeExecveSystem implements ExecveSystem {
  _FakeExecveSystem(this.errors);

  final Map<String, int> errors;
  final List<_ExecveCall> calls = <_ExecveCall>[];
  int _errno = 0;

  @override
  int get errno => _errno;

  @override
  int execve({
    required String path,
    required List<String> arguments,
    required Map<String, String> overlay,
  }) {
    calls.add(_ExecveCall(path: path, arguments: arguments, overlay: overlay));
    _errno = errors[path] ?? 2;
    return -1;
  }
}
