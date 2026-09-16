@Tags(<String>['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final packageDirectory = _packageDirectory();

  test('runtime dependency closure is the vetted set', () {
    final result = Process.runSync('dart', <String>[
      'pub',
      'deps',
      '--json',
    ], workingDirectory: packageDirectory.path);
    if (result.exitCode != 0) {
      fail('`dart pub deps --json` failed: ${result.stderr}');
    }

    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final packages = (data['packages'] as List).cast<Map<String, dynamic>>();
    final byName = <String, Map<String, dynamic>>{
      for (final package in packages) package['name'] as String: package,
    };
    final root = packages.firstWhere(
      (package) => package['name'] == 'keybay_cli',
    );
    final seeds = (root['directDependencies'] as List).cast<String>();
    expect(
      seeds,
      unorderedEquals(<String>[
        'characters',
        'ffi',
        'fleury',
        'fleury_widgets',
        'keybay',
      ]),
    );

    final closure = <String>{};
    final queue = <String>[...seeds];
    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!closure.add(name)) continue;
      final package = byName[name];
      if (package == null) continue;
      queue.addAll((package['directDependencies'] as List).cast<String>());
    }

    expect(
      closure,
      unorderedEquals(<String>{
        'keybay',
        'archive',
        'args',
        'async',
        'characters',
        'fleury',
        'fleury_widgets',
        'image',
        'path',
        'posix',
        'stdio',
        'vm_service',
        'watcher',
        'collection',
        'crypto',
        'cryptography',
        'dbus',
        'ffi',
        'meta',
        'petitparser',
        'typed_data',
        'xml',
      }),
      reason:
          'runtime dependency closure changed; review the supply chain '
          'before updating this expectation',
    );

    for (final name in closure) {
      final source = byName[name]?['source'];
      if (name == 'keybay') {
        expect(
          source,
          'root',
          reason: 'keybay must resolve from the workspace',
        );
      } else if (name == 'fleury' || name == 'fleury_widgets') {
        expect(source, 'git');
      } else {
        expect(
          source,
          'hosted',
          reason: 'package "$name" must resolve from the hosted registry',
        );
      }
    }
  });

  test('runtime dependencies are exact-pinned without overrides', () {
    final pubspec = File(
      '${packageDirectory.path}/pubspec.yaml',
    ).readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(
      pubspec,
      contains(
        RegExp(
          '^\\s*keybay:\\s*${RegExp.escape(packageVersion)}\\s*\$',
          multiLine: true,
        ),
      ),
    );
    expect(
      pubspec,
      contains(RegExp(r'^\s*ffi:\s*2\.2\.0\s*$', multiLine: true)),
    );
    expect(pubspec, contains('url: https://github.com/danReynolds/fleury.git'));
    expect(
      pubspec,
      contains(RegExp(r'^      ref: [0-9a-f]{40}\s*$', multiLine: true)),
    );
    expect(pubspec, isNot(contains('dependency_overrides')));
    expect(
      File('${packageDirectory.path}/pubspec_overrides.yaml').existsSync(),
      isFalse,
    );
    expect(
      File(
        '${packageDirectory.path}/../../pubspec_overrides.yaml',
      ).existsSync(),
      isFalse,
    );
    // The workspace may override fleury's source — fleury_widgets declares it
    // from the hosted registry, which pub will not unify with a git pin — but
    // only onto the very commit this package already names. An override that
    // could substitute different Fleury code is what the ban is for.
    final pins = RegExp(
      r'^      ref: ([0-9a-f]{40})\s*$',
      multiLine: true,
    ).allMatches(pubspec).map((match) => match.group(1)!).toList();
    expect(pins, hasLength(2));
    expect(
      pins.toSet(),
      hasLength(1),
      reason: 'fleury and fleury_widgets must use the same reviewed commit',
    );
    final pinned = pins.first;
    final workspace = File(
      '${packageDirectory.path}/../../pubspec.yaml',
    ).readAsStringSync();
    final overrides = workspace.contains('dependency_overrides')
        ? workspace.substring(workspace.indexOf('dependency_overrides'))
        : '';
    for (final override in RegExp(
      r'^  ([a-z_]+):\s*$',
      multiLine: true,
    ).allMatches(overrides)) {
      expect(
        override.group(1),
        'fleury',
        reason: "only fleury's source may be overridden",
      );
    }
    if (overrides.isNotEmpty) {
      expect(
        overrides,
        contains('ref: $pinned'),
        reason: 'an override must name the pinned Fleury commit',
      );
    }
  });

  test('CLI source contains no network client, file writer, or spawn fallback', () {
    final roots = <Directory>[
      Directory('${packageDirectory.path}/lib'),
      Directory('${packageDirectory.path}/bin'),
    ];
    final forbidden = RegExp(
      r'(?:\b(?:Socket|RawSocket|HttpClient|WebSocket|InternetAddress|NetworkInterface|IOSink|Link)\b|Process\.(?:run|runSync|start)\b|FileMode\.(?:write|append|writeOnly|writeOnlyAppend)\b|\.(?:writeAsBytes|writeAsString|openWrite)(?:Sync)?\s*\()',
    );
    final fileConstructor = RegExp(
      r'\bFile(?:\.(?:fromRawPath|fromUri))?\s*\(',
    );

    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (fileConstructor.hasMatch(source)) {
          expect(
            entity.uri.pathSegments.last,
            isIn([
              'entrypoint.dart',
              'process_executor.dart',
              'clipboard.dart',
            ]),
            reason:
                'Only selected manifest input and executable metadata may construct File objects.',
          );
        }
        expect(
          entity.path.endsWith('/tui/clipboard.dart')
              ? source.replaceAll('Process.start', 'ReviewedClipboardStart')
              : source,
          isNot(matches(forbidden)),
          reason:
              '${entity.path} introduces a network, plaintext file-write, or '
              'spawn API; SR-2, SR-3, SR-8, and SR-13 require review before '
              'adding that surface',
        );
      }
    }
  });
}

Directory _packageDirectory() {
  final nested = Directory('${Directory.current.path}/packages/keybay_cli');
  return nested.existsSync() ? nested : Directory.current;
}
