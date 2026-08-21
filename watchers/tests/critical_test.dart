import 'package:test/test.dart';

import '../critical/watcher.dart';

const config = <String, Object?>{
  'packages': <Object?>[
    <String, Object?>{
      'ecosystem': 'Pub',
      'name': 'cryptography',
      'reviewed_version': '2.9.0',
      'url': 'https://pub.dev/packages/cryptography',
    },
  ],
};

void main() {
  test('reviewed critical version is quiet', () async {
    final found = await criticalFindings(
      config,
      latestVersion: (_) async => '2.9.0',
    );
    expect(found, isEmpty);
  });

  test('new critical version is issue-ready', () async {
    final found = await criticalFindings(
      config,
      latestVersion: (_) async => '2.10.0+1',
    );
    expect(found, hasLength(1));
    expect(
      found.single.marker,
      'keybay-critical-pub-cryptography-2.10.0-1',
    );
  });
}
