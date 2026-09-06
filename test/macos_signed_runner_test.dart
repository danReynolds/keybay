import 'dart:io';

import 'package:test/test.dart';

import 'support/clean_tool_repo.dart';

void main() {
  test(
    'signed runner verifies the rebuilt app and restores on every exit',
    () async {
      final temp = Directory.systemTemp.createTempSync('keybay-signed-runner-');
      const config = 'example_flutter/macos/Runner/Configs/AppInfo.xcconfig';
      const entitlements =
          'example_flutter/macos/Runner/DebugProfile.entitlements';
      try {
        final repo = await stageCleanToolRepo(temp, Directory.current.path, [
          'tool/test_macos_signed.sh',
          config,
          entitlements,
        ]);
        final originalConfig = File('${repo.path}/$config').readAsBytesSync();
        final originalEntitlements = File(
          '${repo.path}/$entitlements',
        ).readAsBytesSync();
        final bin = Directory('${temp.path}/bin')..createSync();
        final programs = {
          'uname': 'echo Darwin',
          'xcodebuild': 'exit 0',
          'flutter': r'''
python3 - "$@" <<'PY'
import json, os, pathlib, plistlib, re, sys
app = pathlib.Path('build/macos/Build/Products/Debug/example_flutter.app/Contents')
(app / 'MacOS').mkdir(parents=True, exist_ok=True)
numbers = re.findall(r'FLUTTER_BUILD_NUMBER = (\d+)', pathlib.Path('macos/Runner/Configs/AppInfo.xcconfig').read_text())
number = numbers[-1] if numbers else '1'
with (app / 'Info.plist').open('wb') as target:
    plistlib.dump({'CFBundleExecutable': 'fixture', 'CFBundleVersion': number}, target)
(app / 'MacOS/fixture').write_text(number)
pathlib.Path(os.environ['FIXTURE_SIGNED_ROOT'], 'build-number').write_text(number)
if '--file-reporter' in sys.argv:
    path = sys.argv[sys.argv.index('--file-reporter') + 1].removeprefix('json:')
    phase = next((arg.split('=')[-1] for arg in sys.argv if arg.startswith('--dart-define=KEYBAY_MACOS_CONTINUITY_PHASE=')), 'baseline')
    if os.environ.get('FIXTURE_REPEATED_SEED') == '1' and phase == 'reopen': phase = 'seed'
    name = ('entitled macOS V2 profile is isolated and resettable' if phase == 'baseline' else
            'signed macOS ' + phase + ' phase preserves its V2 store across replacement')
    events = [{'type': 'testStart', 'test': {'id': 1, 'name': name}},
              {'type': 'testDone', 'testID': 1, 'result': 'success', 'skipped': os.environ.get('FIXTURE_SKIP') == '1'},
              {'type': 'done', 'success': True}]
    pathlib.Path(path).write_text(''.join(json.dumps(event) + '\n' for event in events))
PY
if [[ "$1" == test ]]; then
  touch "$FIXTURE_SIGNED_ROOT/rebuilt"
  exit "${FIXTURE_TEST_EXIT:-0}"
fi
''',
          'cp': r'''
if [[ "$#" == 2 && "${FIXTURE_RESTORE_FAIL:-0}" == 1 ]]; then exit 44; fi
exec /bin/cp "$@"
''',
          'codesign': r'''
if [[ "$1" == --verify ]]; then
  printf '%s\n' "$*" >> "$FIXTURE_SIGNED_ROOT/verifications"
  exit 0
fi
if [[ "$1" == -dv ]]; then
  if [[ "${FIXTURE_SAME_HASH:-0}" == 1 ]]; then echo CDHash=unchanged;
  else printf 'CDHash=build-%s\n' "$(cat "$FIXTURE_SIGNED_ROOT/build-number")"; fi
  exit 0
fi
python3 - "$FIXTURE_SIGNED_ROOT" <<'PY'
import os, pathlib, plistlib, sys
identifier = 'ABCDEFGHIJ.dev.keybay.securityharness'
groups = [identifier]
if pathlib.Path(sys.argv[1], 'rebuilt').exists() and os.environ.get('FIXTURE_EXTRA_GROUP') == '1':
    groups.append('ABCDEFGHIJ.unexpected')
plistlib.dump({'com.apple.application-identifier': identifier,
              'keychain-access-groups': groups,
              'com.apple.security.app-sandbox': True}, sys.stdout.buffer)
PY
''',
        };
        for (final entry in programs.entries) {
          final file = File('${bin.path}/${entry.key}')
            ..writeAsStringSync(
              '#!/usr/bin/env bash\nset -euo pipefail\n${entry.value}\n',
            );
          expect(Process.runSync('chmod', ['700', file.path]).exitCode, 0);
        }
        for (final (environment, expected) in <(Map<String, String>, int)>[
          ({}, 0),
          ({'FIXTURE_TEST_EXIT': '27'}, 27),
          ({'FIXTURE_EXTRA_GROUP': '1'}, 1),
          ({'FIXTURE_SAME_HASH': '1'}, 1),
          ({'FIXTURE_SKIP': '1'}, 1),
          ({'FIXTURE_REPEATED_SEED': '1'}, 1),
          ({'FIXTURE_RESTORE_FAIL': '1'}, 1),
        ]) {
          final rebuilt = File('${temp.path}/rebuilt');
          final verifications = File('${temp.path}/verifications');
          if (rebuilt.existsSync()) rebuilt.deleteSync();
          if (verifications.existsSync()) verifications.deleteSync();
          final result = await Process.run(
            'bash',
            ['tool/test_macos_signed.sh'],
            workingDirectory: repo.path,
            environment: {
              'PATH': '${bin.path}:${Platform.environment['PATH']}',
              'TMPDIR': temp.path,
              'KEYBAY_APPLE_TEAM_ID': 'ABCDEFGHIJ',
              'FIXTURE_SIGNED_ROOT': temp.path,
              ...environment,
            },
          );
          expect(
            result.exitCode,
            expected,
            reason: '${result.stdout}\n${result.stderr}',
          );
          final calls = verifications.readAsLinesSync();
          expect(
            calls,
            hasLength(
              environment.containsKey('FIXTURE_TEST_EXIT')
                  ? 1
                  : environment.containsKey('FIXTURE_EXTRA_GROUP')
                  ? 2
                  : 4,
            ),
          );
          for (final call in calls) {
            expect(call, contains('--deep --strict'));
            expect(call, contains('-R =anchor apple generic'));
            expect(
              call,
              contains('certificate leaf[subject.OU] = "ABCDEFGHIJ"'),
            );
          }
          if (environment.containsKey('FIXTURE_RESTORE_FAIL')) {
            expect(result.stderr, contains('backup retained at'));
            final backupPath = RegExp(
              r'backup retained at (.+)',
            ).firstMatch(result.stderr as String)!.group(1)!;
            final backup = Directory(backupPath);
            expect(
              backup.resolveSymbolicLinksSync(),
              startsWith('${temp.resolveSymbolicLinksSync()}/'),
            );
            expect(
              File('$backupPath/AppInfo.xcconfig').readAsBytesSync(),
              originalConfig,
            );
            expect(
              File('$backupPath/DebugProfile.entitlements').readAsBytesSync(),
              originalEntitlements,
            );
          } else {
            expect(
              File('${repo.path}/$config').readAsBytesSync(),
              originalConfig,
            );
            expect(
              File('${repo.path}/$entitlements').readAsBytesSync(),
              originalEntitlements,
            );
          }
        }
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );
}
