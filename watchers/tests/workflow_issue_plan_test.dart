import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('public advisory workflow plans an issue for a new finding', () async {
    final temp = await Directory.systemTemp.createTemp('keybay-issue-plan.');
    addTearDown(() => temp.delete(recursive: true));

    final payloadDirectory = Directory(
      '${temp.path}/advisory-findings',
    )..createSync();
    File('${payloadDirectory.path}/advisory-findings.json').writeAsStringSync(
      jsonEncode(<Map<String, Object>>[
        <String, Object>{
          'watcher': 'platforms',
          'marker': 'keybay-platform-android-2026-09-01',
          'title': 'Android platform advisory triage: 2026-09-01',
          'subjects': <String>['Android Security Bulletin 2026-09-01'],
          'references': <Map<String, String>>[
            <String, String>{
              'label': 'Android Security Bulletin 2026-09-01',
              'url': 'https://source.android.com/docs/security/bulletin/'
                  '2026-09-01',
            },
          ],
        },
      ]),
    );

    final capture = Directory('${temp.path}/capture')..createSync();
    final fakeGh = File('${temp.path}/gh')..writeAsStringSync('''
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1 \$2" == "issue list" ]]; then
  exit 0
fi
if [[ "\$1 \$2" != "issue create" ]]; then
  exit 2
fi
shift 2
while (( \$# )); do
  case "\$1" in
    --title)
      printf '%s' "\$2" > "\$GH_CAPTURE/title"
      shift 2
      ;;
    --body)
      printf '%s' "\$2" > "\$GH_CAPTURE/body"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
''');
    final chmod = await Process.run('/bin/chmod', <String>[
      '700',
      fakeGh.path,
    ]);
    expect(chmod.exitCode, 0, reason: chmod.stderr as String?);

    final workflow = await File(
      '.github/workflows/security-watchers.yml',
    ).readAsString();
    final script = _workflowRunScript(
      workflow,
      job: 'public-advisory-triage',
      step: 'create missing triage issues',
      nextJob: 'critical-dependencies',
    );
    final result = await Process.run(
      '/bin/bash',
      <String>['-c', script],
      environment: <String, String>{
        'PATH': '${temp.path}:${Platform.environment['PATH']!}',
        'RUNNER_TEMP': temp.path,
        'GH_CAPTURE': capture.path,
        'GITHUB_REPOSITORY': 'example/keybay',
        'GITHUB_RUN_ID': '1234',
        'GITHUB_SERVER_URL': 'https://github.com',
        'GITHUB_SHA': 'abc123',
        'GH_TOKEN': 'test-token',
      },
    );

    expect(result.exitCode, 0, reason: result.stderr as String?);
    expect(
      File('${capture.path}/title').readAsStringSync(),
      'Android platform advisory triage: 2026-09-01',
    );
    final body = File('${capture.path}/body').readAsStringSync();
    expect(body, contains('keybay-platform-android-2026-09-01'));
    expect(body, contains('Android Security Bulletin 2026-09-01'));
    expect(body, contains('actions/runs/1234'));
    expect(body, contains('source commit `abc123`'));
  });
}

String _workflowRunScript(
  String workflow, {
  required String job,
  required String step,
  required String nextJob,
}) {
  final jobStart = workflow.indexOf('  $job:');
  final stepStart = workflow.indexOf('      - name: $step', jobStart);
  final runStart = workflow.indexOf('        run: |\n', stepStart);
  final jobEnd = workflow.indexOf('\n  $nextJob:', runStart);
  if ([jobStart, stepStart, runStart, jobEnd].any((offset) => offset < 0)) {
    throw StateError('workflow issue step was not found');
  }
  final block =
      workflow.substring(runStart + '        run: |\n'.length, jobEnd);
  return block
      .split('\n')
      .map((line) => line.startsWith('          ') ? line.substring(10) : line)
      .join('\n');
}
