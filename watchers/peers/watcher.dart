import 'dart:collection';
import 'dart:io';

import '../finding.dart';
import '../http.dart';
import '../osv.dart';

typedef AdvisoryLookup = Future<Set<String>> Function(
  String ecosystem,
  String name,
);

typedef ActivityLookup = Future<List<PeerActivity>> Function(
  String repository,
  DateTime since,
);

const peers = <({String ecosystem, String name, String repository})>[
  (
    ecosystem: 'Pub',
    name: 'flutter_secure_storage',
    repository: 'juliansteenbakker/flutter_secure_storage',
  ),
  (
    ecosystem: 'PyPI',
    name: 'keyring',
    repository: 'jaraco/keyring',
  ),
  (
    ecosystem: 'npm',
    name: 'react-native-keychain',
    repository: 'oblador/react-native-keychain',
  ),
  (
    ecosystem: 'npm',
    name: 'keytar',
    repository: 'atom/node-keytar',
  ),
  (
    ecosystem: 'Go',
    name: 'github.com/zalando/go-keyring',
    repository: 'zalando/go-keyring',
  ),
  (
    ecosystem: 'crates.io',
    name: 'keyring',
    repository: 'open-source-cooperative/keyring-rs',
  ),
];

final class PeerActivity {
  const PeerActivity({
    required this.kind,
    required this.identifier,
    required this.title,
    required this.updatedAt,
    required this.url,
  });

  final String kind;
  final String identifier;
  final String title;
  final DateTime updatedAt;
  final String url;
}

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
          'peer source returned an unsafe advisory ID: $id',
        );
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

Future<List<PeerActivity>> githubActivity(
  String repository,
  DateTime since,
) async {
  final headers = <String, String>{
    HttpHeaders.acceptHeader: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    if (Platform.environment['GITHUB_TOKEN'] case final token?
        when token.isNotEmpty)
      HttpHeaders.authorizationHeader: 'Bearer $token',
  };
  final found = <PeerActivity>[];
  await _readPages(
    repository,
    Uri.https(
      'api.github.com',
      '/repos/$repository/issues',
      <String, String>{
        'state': 'all',
        'sort': 'updated',
        'direction': 'desc',
        'since': since.toUtc().toIso8601String(),
        'per_page': '100',
      },
    ),
    headers,
    (item) {
      final updatedAt = _githubDate(item['updated_at'], repository);
      if (updatedAt.isBefore(since)) return false;
      final number = item['number'];
      if (number is! int || number < 1) {
        throw FormatException('$repository returned an invalid issue number');
      }
      final kind = item.containsKey('pull_request') ? 'pull-request' : 'issue';
      found.add(
        PeerActivity(
          kind: kind,
          identifier: '$number',
          title: _cleanTitle(item['title'], repository),
          updatedAt: updatedAt,
          url: _githubUrl(item['html_url'], repository),
        ),
      );
      return true;
    },
  );
  await _readPages(
    repository,
    Uri.https(
      'api.github.com',
      '/repos/$repository/releases',
      <String, String>{'per_page': '100'},
    ),
    headers,
    (item) {
      final updatedAt = _githubDate(
        item['published_at'] ?? item['created_at'],
        repository,
      );
      if (updatedAt.isBefore(since)) return false;
      final tag = item['tag_name'];
      if (tag is! String || tag.isEmpty || tag.length > 100) {
        throw FormatException('$repository returned an invalid release tag');
      }
      found.add(
        PeerActivity(
          kind: 'release',
          identifier: tag,
          title: _cleanTitle(item['name'] ?? tag, repository),
          updatedAt: updatedAt,
          url: _githubUrl(item['html_url'], repository),
        ),
      );
      return true;
    },
  );
  found.sort((left, right) {
    final time = right.updatedAt.compareTo(left.updatedAt);
    return time == 0 ? left.url.compareTo(right.url) : time;
  });
  return found;
}

Future<List<WatcherFinding>> peerFindings(
  Set<String> baseline, {
  AdvisoryLookup? advisoryLookup,
  ActivityLookup? activityLookup,
  DateTime? now,
  int activityLookbackDays = 14,
}) async {
  if (activityLookbackDays < 1 || activityLookbackDays > 31) {
    throw const FormatException('peer activity lookback must be 1 to 31 days');
  }
  final found = await newPeerAdvisories(baseline, lookup: advisoryLookup);
  final findings = <WatcherFinding>[
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
  final findActivity = activityLookup ?? githubActivity;
  final since = (now ?? DateTime.now().toUtc())
      .toUtc()
      .subtract(Duration(days: activityLookbackDays));
  for (final peer in peers) {
    final activity = await findActivity(peer.repository, since);
    for (final item in activity) {
      final updated = item.updatedAt.toUtc().millisecondsSinceEpoch;
      final identifier = _markerComponent(item.identifier);
      findings.add(
        WatcherFinding(
          watcher: 'peers',
          marker:
              'keybay-peer-github-${peer.repository}-${item.kind}-$identifier-$updated',
          title: 'Peer ${item.kind}: ${item.title}',
          subjects: <String>[peer.repository],
          references: <({String label, String url})>[
            (label: '${item.kind} ${item.identifier}', url: item.url),
          ],
        ),
      );
    }
  }
  return findings;
}

Future<void> _readPages(
  String repository,
  Uri first,
  Map<String, String> headers,
  bool Function(Map<String, Object?> item) accept,
) async {
  for (var page = 1; page <= 5; page++) {
    final uri = first.replace(
      queryParameters: <String, String>{
        ...first.queryParameters,
        'page': '$page',
      },
    );
    final raw = await fetchJson(uri, headers: headers);
    if (raw is! List) {
      throw FormatException('$repository returned a non-list GitHub response');
    }
    for (final rawItem in raw) {
      if (rawItem is! Map) {
        throw FormatException('$repository returned a malformed GitHub item');
      }
      final keepReading = accept(<String, Object?>{
        for (final entry in rawItem.entries)
          if (entry.key is String) entry.key as String: entry.value,
      });
      if (!keepReading) return;
    }
    if (raw.length < 100) return;
  }
  throw FormatException('$repository exceeded the five-page safety bound');
}

DateTime _githubDate(Object? value, String repository) {
  if (value is! String) {
    throw FormatException('$repository returned a missing GitHub timestamp');
  }
  final parsed = DateTime.tryParse(value)?.toUtc();
  if (parsed == null) {
    throw FormatException('$repository returned an invalid GitHub timestamp');
  }
  return parsed;
}

String _githubUrl(Object? value, String repository) {
  if (value is! String) {
    throw FormatException('$repository returned a missing GitHub URL');
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
    throw FormatException('$repository returned an invalid GitHub URL');
  }
  return uri.toString();
}

String _cleanTitle(Object? value, String repository) {
  if (value is! String) {
    throw FormatException('$repository returned a missing title');
  }
  final cleaned = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  if (cleaned.isEmpty) {
    throw FormatException('$repository returned an empty title');
  }
  return cleaned.length <= 160 ? cleaned : '${cleaned.substring(0, 157)}...';
}

String _markerComponent(String value) {
  final component = value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '-');
  if (component.isEmpty) {
    throw const FormatException('peer activity identifier was unsafe');
  }
  return component;
}
