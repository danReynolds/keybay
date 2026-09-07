import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:test/test.dart';

import 'support/clean_tool_repo.dart';

void main() {
  late Directory temp;
  late Directory repository;
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('keybay-regression-test-');
    repository = await stageCleanToolRepo(temp, Directory.current.path, [
      'tool/test_e2e.sh',
      'tool/platform_regression.dart',
    ]);
    for (final name in [
      'core',
      'macos_native',
      'linux',
      'flatpak',
      'macos_signed',
      'macos_developer_id',
    ]) {
      File('${repository.path}/tool/test_$name.sh').writeAsStringSync('''
printf '%s\\n' '$name' >> invocations
exit "\${FIXTURE_${name.toUpperCase()}_EXIT:-0}"
''');
    }
    File('${repository.path}/tool/test_mobile_ci.sh').writeAsStringSync(r'''
printf '%s\n' "$1" >> invocations
exit "${FIXTURE_MOBILE_EXIT:-0}"
''');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> run(
    List<String> args, [
    Map<String, String>? env,
  ]) => Process.run(
    'bash',
    ['${repository.path}/tool/test_e2e.sh', ...args],
    // The entrypoint must work from outside the repository too.
    workingDirectory: temp.path,
    environment: {
      'PATH':
          '${File(Platform.resolvedExecutable).parent.path}:${Platform.environment['PATH']}',
      ...?env,
    },
  );

  Map<String, Object?> report() {
    final files = Directory('${repository.path}/build/regression')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('/report.json'));
    return jsonDecode(files.single.readAsStringSync()) as Map<String, Object?>;
  }

  test(
    'subset preserves order, runs once, and writes a finished report',
    () async {
      final result = await run(['flatpak', 'linux', 'flatpak']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(File('${repository.path}/invocations').readAsLinesSync(), [
        'flatpak',
        'linux',
      ]);
      final receipt = report();
      expect(receipt['status'], 'pass');
      expect(receipt['dartAbi'], Abi.current().toString());
      expect(receipt['sourceCommit'], matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(receipt['sourceDirty'], isTrue);
      expect(receipt['finishedUtc'], isNotNull);
      expect(receipt['results'], [
        {'platform': 'flatpak', 'status': 'pass', 'exitCode': 0},
        {'platform': 'linux', 'status': 'pass', 'exitCode': 0},
      ]);
    },
  );

  test(
    'failures and blocked platforms do not hide subsequent results',
    () async {
      final result = await run(
        ['linux', 'flatpak', 'android'],
        {'FIXTURE_LINUX_EXIT': '23', 'FIXTURE_FLATPAK_EXIT': '69'},
      );
      expect(result.exitCode, 1);
      final receipt = report();
      expect(receipt['status'], 'fail');
      expect(receipt['results'], [
        {'platform': 'linux', 'status': 'fail', 'exitCode': 23},
        {'platform': 'flatpak', 'status': 'blocked', 'exitCode': 69},
        {'platform': 'android', 'status': 'pass', 'exitCode': 0},
      ]);
    },
  );

  test('a missing prerequisite is a nonzero blocked result', () async {
    final result = await run(['linux'], {'FIXTURE_LINUX_EXIT': '69'});
    expect(result.exitCode, 69);
    expect(report()['status'], 'blocked');
  });

  for (final args in [
    <String>[],
    ['all'],
  ]) {
    test(
      'selection $args includes every routine lane and excludes signing',
      () async {
        final result = await run(args);
        expect(result.exitCode, Platform.isMacOS ? 0 : 69);
        final receipt = report();
        expect(
          (receipt['results'] as List).cast<Map<String, Object?>>().map(
            (value) => value['platform'],
          ),
          ['core', 'macos', 'linux', 'flatpak', 'android', 'ios'],
        );
        expect(
          File('${repository.path}/invocations').readAsLinesSync(),
          isNot(contains('macos_signed')),
        );
        if (!Platform.isMacOS) {
          expect(((receipt['results'] as List)[1] as Map)['status'], 'blocked');
          expect(((receipt['results'] as List)[5] as Map)['status'], 'blocked');
        }
      },
    );
  }

  test('Developer ID qualification is an explicit signing lane', () async {
    final result = await run(['macos-developer-id']);
    expect(result.exitCode, Platform.isMacOS ? 0 : 69);
    expect((report()['results'] as List).single, {
      'platform': 'macos-developer-id',
      'status': Platform.isMacOS ? 'pass' : 'blocked',
      'exitCode': Platform.isMacOS ? 0 : 69,
    });
  });

  test(
    'invalid selections and help have no test or report side effects',
    () async {
      for (final args in [
        ['linux', 'typo'],
        ['all', 'linux'],
        ['--help'],
      ]) {
        final result = await run(args);
        expect(result.exitCode, args.singleOrNull == '--help' ? 0 : 64);
        expect(Directory('${repository.path}/build').existsSync(), isFalse);
        expect(File('${repository.path}/invocations').existsSync(), isFalse);
      }
    },
  );

  test(
    'interruption stops scheduling and leaves pending lanes unpassed',
    () async {
      final result = await run(
        ['linux', 'flatpak'],
        {'FIXTURE_LINUX_EXIT': '130'},
      );
      expect(result.exitCode, 130);
      expect(File('${repository.path}/invocations').readAsLinesSync(), [
        'linux',
      ]);
      final receipt = report();
      expect(receipt['status'], 'interrupted');
      expect(((receipt['results'] as List)[1] as Map)['status'], 'not-run');
      expect(receipt['finishedUtc'], isNull);
    },
  );

  test('CI selects the maintained SDK runners', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    for (final name in [
      'core',
      'macos',
      'linux',
      'flatpak',
      'android',
      'ios',
    ]) {
      expect(workflow, contains('./tool/test_e2e.sh $name'));
    }
    expect(
      File('tool/test_core.sh').readAsStringSync(),
      contains('dart test -x integration'),
    );
    expect(workflow, contains('path: build/regression/*/report.json'));
  });
}
