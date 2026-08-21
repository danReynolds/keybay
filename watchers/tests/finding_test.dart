import 'package:test/test.dart';

import '../finding.dart';

void main() {
  test('finding emits the workflow JSON contract', () {
    const finding = WatcherFinding(
      watcher: 'platforms',
      marker: 'keybay-platform-example',
      title: 'Example triage',
      subjects: <String>['Example subject'],
      references: <({String label, String url})>[
        (label: 'Example', url: 'https://example.com/advisory'),
      ],
    );

    expect(finding.toJson(), <String, Object>{
      'watcher': 'platforms',
      'marker': 'keybay-platform-example',
      'title': 'Example triage',
      'subjects': <String>['Example subject'],
      'references': <Map<String, String>>[
        <String, String>{
          'label': 'Example',
          'url': 'https://example.com/advisory',
        },
      ],
    });
  });
}
