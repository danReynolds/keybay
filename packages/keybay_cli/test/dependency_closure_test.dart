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
        'keybay',
        'keypass',
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
        'keypass',
        'code_assets',
        'hooks',
        'record_use',
        'logging',
        'pub_semver',
        'source_span',
        'string_scanner',
        'term_glyph',
        'yaml',
        'archive',
        'args',
        'async',
        'characters',
        'fleury',
        'image',
        'path',
        'posix',
        'stdio',
        'vm_service',
        'watcher',
        'collection',
        'convert',
        'crypto',
        'cryptography',
        'dbus',
        'ffi',
        'meta',
        'petitparser',
        'pointycastle',
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
      } else {
        expect(
          source,
          'hosted',
          reason: 'package "$name" must resolve from the hosted registry',
        );
      }
    }
    // Keybay's companion firewall checks the exact Keypass hosted archive/source
    // and complete hosted closure. Keep the CLI's new verification dependency
    // versions explicit here as well.
    expect(byName['fleury']?['version'], '0.1.1');
    expect(byName['keypass']?['version'], '0.1.0-dev.2');
    expect(byName['pointycastle']?['version'], '4.0.0');
    expect(byName['convert']?['version'], '3.1.2');
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
    expect(pubspec, contains(RegExp(r'^  fleury: 0\.1\.1$', multiLine: true)));
    expect(pubspec, isNot(contains('git:')));
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
    expect(
      pubspec,
      contains(RegExp(r'^  keypass: 0\.1\.0-dev\.2$', multiLine: true)),
    );
    final workspace = File(
      '${packageDirectory.path}/../../pubspec.yaml',
    ).readAsStringSync();
    expect(workspace, isNot(contains('dependency_overrides')));
  });

  test(
    'CLI I/O stays within reviewed input, preference and clipboard boundaries',
    () {
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
                'unlock_preference_file.dart',
                'appearance_file.dart',
              ]),
              reason:
                  'Only reviewed manifest, metadata, clipboard and nonsecret preference code may construct File objects.',
            );
          }
          final reviewedSource =
              entity.path.endsWith('/unlock_preference_file.dart') ||
                  entity.path.endsWith('/appearance_file.dart')
              ? source.replaceAll(
                  'stage.writeAsString(',
                  'ReviewedPreferenceWrite(',
                )
              : entity.path.endsWith('/tui/clipboard.dart')
              ? source.replaceAll('Process.start', 'ReviewedClipboardStart')
              : source;
          expect(
            reviewedSource,
            isNot(matches(forbidden)),
            reason:
                '${entity.path} introduces a network, plaintext file-write, or '
                'spawn API; SR-2, SR-3, SR-8, and SR-13 require review before '
                'adding that surface',
          );
        }
      }
    },
  );
}

Directory _packageDirectory() {
  final nested = Directory('${Directory.current.path}/packages/keybay_cli');
  return nested.existsSync() ? nested : Directory.current;
}
