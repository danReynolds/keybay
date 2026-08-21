import 'package:test/test.dart';

import '../peers/watcher.dart';

void main() {
  test('peer baseline IDs are suppressed', () async {
    final found = await newPeerAdvisories(
      <String>{'OLD-1'},
      lookup: (ecosystem, name) async => <String>{'OLD-1'},
    );
    expect(found, isEmpty);
  });

  test('new peer ID groups every affected peer', () async {
    final found = await newPeerAdvisories(
      <String>{},
      lookup: (ecosystem, name) async => name == 'keyring' || name == 'keytar'
          ? <String>{'CVE-2026-1234'}
          : <String>{},
    );
    expect(found, <String, List<String>>{
      'CVE-2026-1234': <String>[
        'PyPI/keyring',
        'crates.io/keyring',
        'npm/keytar',
      ],
    });
  });
}
