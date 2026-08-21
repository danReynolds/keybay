import 'dart:collection';

import '../finding.dart';
import '../osv.dart';

typedef AdvisoryLookup = Future<Set<String>> Function(
  String ecosystem,
  String name,
);

const peers = <({String ecosystem, String name})>[
  (ecosystem: 'Pub', name: 'flutter_secure_storage'),
  (ecosystem: 'PyPI', name: 'keyring'),
  (ecosystem: 'npm', name: 'keytar'),
  (ecosystem: 'Go', name: 'github.com/zalando/go-keyring'),
  (ecosystem: 'crates.io', name: 'keyring'),
];

Future<Set<String>> advisories(String ecosystem, String name) async => {
      for (final record in await queryPackage(ecosystem, name))
        record['id']! as String,
    };

Set<String> peerBaseline(Map<String, Object?> config) {
  final rawBaseline = config['baseline'];
  if (rawBaseline is! List) {
    throw const FormatException('peer baseline was not a list');
  }
  final result = <String>{};
  for (final id in rawBaseline) {
    if (id is! String || !isSafeAdvisoryId(id)) {
      throw FormatException('peer baseline had an unsafe advisory ID: $id');
    }
    result.add(id);
  }
  return result;
}

Future<Map<String, List<String>>> newPeerAdvisories(
  Set<String> baseline, {
  AdvisoryLookup? lookup,
}) async {
  final find = lookup ?? advisories;
  final grouped = SplayTreeMap<String, Set<String>>();
  for (final peer in peers) {
    final found = await find(peer.ecosystem, peer.name);
    for (final id in found.difference(baseline)) {
      if (!isSafeAdvisoryId(id)) {
        throw FormatException(
            'peer source returned an unsafe advisory ID: $id');
      }
      grouped
          .putIfAbsent(id, () => <String>{})
          .add('${peer.ecosystem}/${peer.name}');
    }
  }
  return <String, List<String>>{
    for (final entry in grouped.entries)
      entry.key: (entry.value.toList()..sort()),
  };
}

Future<List<WatcherFinding>> peerFindings(
  Set<String> baseline, {
  AdvisoryLookup? lookup,
}) async {
  final found = await newPeerAdvisories(baseline, lookup: lookup);
  return <WatcherFinding>[
    for (final entry in found.entries)
      WatcherFinding(
        watcher: 'peers',
        marker: 'keybay-peer-osv-${entry.key}',
        title: 'Peer advisory triage: ${entry.key}',
        subjects: entry.value,
        references: <({String label, String url})>[
          (
            label: entry.key,
            url: 'https://osv.dev/vulnerability/${entry.key}',
          ),
        ],
      ),
  ];
}
