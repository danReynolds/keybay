import 'package:test/test.dart';

import '../peers/watcher.dart';

void main() {
  test('peer set covers Flutter, React Native, and native ecosystems', () {
    expect(
      peers,
      contains(
        (
          ecosystem: 'npm',
          name: 'react-native-keychain',
          repository: 'oblador/react-native-keychain',
        ),
      ),
    );
  });

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

  test('peer findings include bounded recent repository activity', () async {
    final now = DateTime.utc(2026, 8, 22, 12);
    final found = await peerFindings(
      <String>{},
      now: now,
      advisoryLookup: (ecosystem, name) async => <String>{},
      activityLookup: (repository, since) async {
        expect(since, DateTime.utc(2026, 8, 8, 12));
        return repository == 'jaraco/keyring'
            ? <PeerActivity>[
                PeerActivity(
                  kind: 'issue',
                  identifier: '777',
                  title: 'Review storage fallback',
                  updatedAt: DateTime.utc(2026, 8, 20),
                  url: 'https://github.com/jaraco/keyring/issues/777',
                ),
              ]
            : <PeerActivity>[];
      },
    );

    expect(found, hasLength(1));
    expect(found.single.watcher, 'peers');
    expect(found.single.title, 'Peer issue: Review storage fallback');
    expect(found.single.subjects, <String>['jaraco/keyring']);
    expect(
      found.single.marker,
      startsWith('keybay-peer-github-jaraco/keyring-issue-777-'),
    );
  });

  test('peer activity lookback is bounded', () async {
    expect(
      () => peerFindings(
        <String>{},
        activityLookbackDays: 32,
        advisoryLookup: (ecosystem, name) async => <String>{},
        activityLookup: (repository, since) async => <PeerActivity>[],
      ),
      throwsFormatException,
    );
  });
}
