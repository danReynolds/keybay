import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'mobile runner keeps console text out of evidence and preserves failures',
    () async {
      final temp = Directory.systemTemp.createTempSync('keybay-mobile-runner.');
      try {
        final bin = Directory('${temp.path}/bin')..createSync();
        final fixture = File('${temp.path}/fixture.jsonl');
        const nonce =
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
        const subject = 'git-commit:0123456789abcdef0123456789abcdef01234567';
        fixture.writeAsStringSync(
          [
            for (final (index, name) in [
              'KEYBAY-SECURITY-METADATA nonce=$nonce subject=$subject',
              'KB-IOS-010 round trip',
              'KB-IOS-020 concurrency',
            ].indexed) ...[
              jsonEncode({
                'type': 'testStart',
                'test': {'id': index, 'name': name},
              }),
              jsonEncode({
                'type': 'testDone',
                'testID': index,
                'result': 'success',
                'skipped': false,
              }),
            ],
            jsonEncode({'type': 'done', 'success': true}),
          ].join('\n'),
        );
        final flutter = File('${bin.path}/flutter')
          ..writeAsStringSync(r'''#!/usr/bin/env bash
set -euo pipefail
reporter=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--file-reporter" ]]; then
    reporter="${2#json:}"
    shift 2
  else
    shift
  fi
done
printf 'non-JSON build output with private-device-id\n'
cp "$KEYBAY_FIXTURE_REPORT" "$reporter"
exit "$KEYBAY_FIXTURE_EXIT"
''');
        expect(Process.runSync('chmod', ['700', flutter.path]).exitCode, 0);
        for (final failure in [0, 7]) {
          final output = File('${temp.path}/$failure.results.json');
          final log = File('${temp.path}/$failure.log');
          final result = await Process.run(
            'bash',
            [
              '-c',
              r'''set -euo pipefail
source "$1"
ds_flutter_security_test private-device-id ios-baseline "$2" "$3"
''',
              'runner-test',
              '${Directory.current.path}/tool/device_security/common.sh',
              log.path,
              output.path,
            ],
            environment: {
              'REPO': Directory.current.path,
              'DEVICE_SECURITY_NONCE': nonce,
              'DEVICE_SECURITY_SOURCE_IDENTITY': subject,
              'KEYBAY_FIXTURE_REPORT': fixture.path,
              'KEYBAY_FIXTURE_EXIT': '$failure',
              'PATH':
                  '${bin.path}:${File(Platform.resolvedExecutable).parent.path}:${Platform.environment['PATH']}',
            },
          );
          expect(result.exitCode, failure, reason: '${result.stderr}');
          final document =
              jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
          expect(document['subject'], subject);
          expect(document['command_status'], 'pass');
          expect(
            (document['scenarios'] as List).cast<Map<String, dynamic>>().map(
              (e) => e['status'],
            ),
            everyElement('pass'),
          );
          expect(log.readAsStringSync(), contains('private-device-id'));
          expect(
            '${result.stdout}${result.stderr}${output.readAsStringSync()}',
            isNot(contains('private-device-id')),
          );
        }
      } finally {
        temp.deleteSync(recursive: true);
      }
    },
  );
}
