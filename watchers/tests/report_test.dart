import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../report.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('keybay-report-test.');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('creates one raw and one pending assessment document', () async {
    final inputs = await _inputs(temp, peerFinding: true);
    final output = Directory('${temp.path}/2026-08-22-123-1');
    await createReport(
      runId: '123',
      attempt: '1',
      event: 'workflow_dispatch',
      commit: 'a' * 40,
      startedAt: DateTime.utc(2026, 8, 22, 12),
      inputs: inputs,
      outputDirectory: output,
    );

    expect(
      output.listSync().map((file) => file.uri.pathSegments.last).toSet(),
      <String>{'raw.md', 'assessment.md'},
    );
    final raw = await File('${output.path}/raw.md').readAsString();
    expect(raw, contains('Peer issue: Storage fallback'));
    expect(raw, contains('Status: **findings**'));
    expect(
      raw,
      contains('https://github.com/danReynolds/keybay/actions/runs/123'),
    );
    final assessment =
        await File('${output.path}/assessment.md').readAsString();
    expect(assessment, contains('"status":"pending"'));
  });

  test('rejects Markdown control characters from untrusted input', () async {
    final inputs = await _inputs(temp);
    final peers = jsonDecode(await inputs['peers']!.readAsString()) as Map;
    peers['status'] = 'findings';
    peers['findings'] = <Object?>[
      _finding(title: 'Injected\n# Heading'),
    ];
    await inputs['peers']!.writeAsString(jsonEncode(peers));

    expect(
      () => createReport(
        runId: '123',
        attempt: '1',
        event: 'schedule',
        commit: 'b' * 40,
        startedAt: DateTime.utc(2026, 8, 22),
        inputs: inputs,
        outputDirectory: Directory('${temp.path}/report'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('summary links raw, assessment, and safe Keybay actions', () async {
    final inputs = await _inputs(temp);
    final reports = Directory('${temp.path}/reports');
    final output = Directory('${reports.path}/2026-08-22-123-1');
    await createReport(
      runId: '123',
      attempt: '1',
      event: 'schedule',
      commit: 'c' * 40,
      startedAt: DateTime.utc(2026, 8, 22),
      inputs: inputs,
      outputDirectory: output,
    );
    final assessment = File('${output.path}/assessment.md');
    await assessment.writeAsString(
      '<!-- keybay-watcher-assessment: '
      '${jsonEncode(<String, Object>{
            'schema': 1,
            'report_id': 'github-123-1',
            'status': 'assessed',
            'summary': 'No applicable Keybay issue found.',
            'actions': <Object>[
              <String, String>{
                'label': 'Issue 99',
                'url': 'https://github.com/danReynolds/keybay/issues/99',
              },
            ],
          })} -->\n\n# Assessment\n',
    );
    final summary = File('${reports.path}/SUMMARY.md');
    await writeSummary(reports, summary);

    final content = await summary.readAsString();
    expect(content, contains('[2026-08-22](2026-08-22-123-1/raw.md)'));
    expect(content, contains('No applicable Keybay issue found.'));
    expect(
        content,
        contains(
            '[Issue 99](https://github.com/danReynolds/keybay/issues/99)'));
  });
}

Future<Map<String, File>> _inputs(
  Directory directory, {
  bool peerFinding = false,
}) async {
  final result = <String, File>{};
  for (final watcher in watcherNames) {
    final findings =
        watcher == 'peers' && peerFinding ? <Object?>[_finding()] : <Object?>[];
    final file = File('${directory.path}/$watcher.json');
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'watcher': watcher,
        'status': findings.isEmpty ? 'quiet' : 'findings',
        'findings': findings,
        'error': null,
      }),
    );
    result[watcher] = file;
  }
  return result;
}

Map<String, Object> _finding({String title = 'Peer issue: Storage fallback'}) =>
    <String, Object>{
      'watcher': 'peers',
      'marker': 'keybay-peer-example',
      'title': title,
      'subjects': <String>['example/peer'],
      'references': <Map<String, String>>[
        <String, String>{
          'label': 'issue 1',
          'url': 'https://github.com/example/peer/issues/1',
        },
      ],
    };
