import 'package:test/test.dart';

import '../dependencies/watcher.dart';

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
  test('reviewed dependency version is quiet', () async {
    final found = await dependencyReleaseFindings(
      config,
      latestVersion: (_) async => '2.9.0',
    );
    expect(found, isEmpty);
  });

  test('new reviewed dependency version is report-ready', () async {
    final found = await dependencyReleaseFindings(
      config,
      latestVersion: (_) async => '2.10.0+1',
    );
    expect(found, hasLength(1));
    expect(
      found.single.marker,
      'keybay-dependency-release-pub-cryptography-2.10.0-1',
    );
  });
}
