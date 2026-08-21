import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;

import '../finding.dart';
import '../http.dart' as http;
import '../osv.dart';

typedef TextFetcher = Future<String> Function(Uri uri);

final _androidPath = RegExp(
  r'^/docs/security/bulletin/(\d{4}-\d{2}-\d{2})$',
);
final _appleUrl = RegExp(r'^https://support\.apple\.com/en-us/(\d{5,9})$');
final _cve = RegExp(r'^CVE-\d{4}-\d{4,}$');
final _safeSubject = RegExp(r'^[^\r\n@`]{1,200}$');
final _timezoneSuffix = RegExp(r'(?:Z|[+-]\d{2}:\d{2})$');

const _months = <String, int>{
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

DateTime parseTimestamp(String value) {
  if (!_timezoneSuffix.hasMatch(value)) {
    throw FormatException('timestamp has no timezone: $value');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('invalid timestamp: $value');
  }
  return parsed.toUtc();
}

List<WatcherFinding> appleFindings(
  String source, {
  required DateTime startedAt,
  required List<String> products,
}) {
  final document = html.parse(source);
  final grouped = SplayTreeMap<String, Set<({String name, String url})>>();
  var sawTableRow = false;
  for (final row in document.querySelectorAll('tr')) {
    final cells =
        row.children.where((element) => element.localName == 'td').toList();
    if (cells.isNotEmpty) {
      sawTableRow = true;
    }
    if (cells.length != 3) {
      continue;
    }
    final name = _normalized(cells[0].text);
    final dateText = _normalized(cells[2].text);
    if (!products.any(name.contains)) {
      continue;
    }
    final releaseDate = _parseAppleDate(dateText);
    if (releaseDate.isBefore(_date(startedAt))) {
      continue;
    }
    String? official;
    for (final link in cells[0].querySelectorAll('a[href]')) {
      final href = link.attributes['href'];
      if (href != null && _appleUrl.hasMatch(href)) {
        official = href;
        break;
      }
    }
    if (official == null) {
      // Apple lists some releases without an advisory link. They are updates,
      // not actionable advisory input for this watcher.
      continue;
    }
    if (!_safeSubject.hasMatch(name)) {
      throw FormatException('unsafe Apple release title: $name');
    }
    grouped
        .putIfAbsent(
            _dateOnly(releaseDate), () => <({String name, String url})>{})
        .add((name: name, url: official));
  }
  if (!sawTableRow) {
    throw const FormatException('Apple security table had no rows');
  }

  return <WatcherFinding>[
    for (final group in grouped.entries) _appleFinding(group.key, group.value),
  ];
}

List<WatcherFinding> androidFindings(
  String source, {
  required Uri indexUri,
  required DateTime startedAt,
}) {
  final document = html.parse(source);
  final dates = SplayTreeSet<String>();
  var sawBulletinLink = false;
  for (final link in document.querySelectorAll('a[href]')) {
    final href = link.attributes['href'];
    if (href == null) {
      continue;
    }
    final absolute = indexUri.resolve(href);
    if (absolute.scheme != 'https' || absolute.host != 'source.android.com') {
      continue;
    }
    final match = _androidPath.firstMatch(absolute.path);
    if (match == null) {
      continue;
    }
    sawBulletinLink = true;
    final date = _parseIsoDate(match.group(1)!);
    if (!date.isBefore(_date(startedAt))) {
      dates.add(_dateOnly(date));
    }
  }
  if (!sawBulletinLink) {
    throw const FormatException('Android bulletin index had no bulletin links');
  }
  return <WatcherFinding>[
    for (final date in dates)
      WatcherFinding(
        watcher: 'platforms',
        marker: 'keybay-platform-android-$date',
        title: 'Android platform advisory triage: $date',
        subjects: <String>['Android Security Bulletin $date'],
        references: <({String label, String url})>[
          (
            label: 'Android Security Bulletin $date',
            url: 'https://source.android.com/docs/security/bulletin/$date',
          ),
        ],
      ),
  ];
}

Future<List<WatcherFinding>> linuxFindings({
  required DateTime startedAt,
  required List<String> ecosystems,
  required List<String> packages,
  OsvQuery? query,
}) async {
  final lookup = query ?? queryPackage;
  final grouped = SplayTreeMap<String, _LinuxGroup>();
  for (final ecosystem in ecosystems) {
    for (final package in packages) {
      for (final record in await lookup(ecosystem, package)) {
        if (_recordTime(record).isBefore(startedAt)) {
          continue;
        }
        final canonical = _canonicalLinuxId(record);
        final group = grouped.putIfAbsent(canonical, _LinuxGroup.new);
        group.records.add(record['id']! as String);
        group.subjects.add('$ecosystem/$package');
      }
    }
  }
  return <WatcherFinding>[
    for (final entry in grouped.entries)
      WatcherFinding(
        watcher: 'platforms',
        marker: 'keybay-platform-linux-${entry.key}',
        title: 'Linux credential-platform advisory triage: ${entry.key}',
        subjects: entry.value.subjects.toList()..sort(),
        references: <({String label, String url})>[
          for (final id in entry.value.records.toList()..sort())
            (label: id, url: 'https://osv.dev/vulnerability/$id'),
        ],
      ),
  ];
}

Future<List<WatcherFinding>> platformFindings(
  Map<String, Object?> config, {
  TextFetcher? fetch,
  OsvQuery? query,
}) async {
  final startedAtValue = config['started_at'];
  if (startedAtValue is! String) {
    throw const FormatException('platform started_at must be a timestamp');
  }
  final startedAt = parseTimestamp(startedAtValue);
  final apple = _object(config['apple'], 'Apple source definition');
  final android = _object(config['android'], 'Android source definition');
  final linux = _object(config['linux'], 'Linux source definition');
  final appleIndex = apple['index'];
  final androidIndex = android['index'];
  if (appleIndex != 'https://support.apple.com/en-us/100100') {
    throw const FormatException('unexpected Apple security index');
  }
  if (androidIndex != 'https://source.android.com/docs/security/bulletin') {
    throw const FormatException('unexpected Android bulletin index');
  }
  final products = _stringList(apple['products'], 'Apple products');
  final ecosystems = _stringList(linux['ecosystems'], 'Linux ecosystems');
  final packages = _stringList(linux['packages'], 'Linux packages');
  final load = fetch ?? http.fetchText;
  final appleUri = Uri.parse(appleIndex as String);
  final androidUri = Uri.parse(androidIndex as String);
  final result = <WatcherFinding>[
    ...appleFindings(
      await load(appleUri),
      startedAt: startedAt,
      products: products,
    ),
    ...androidFindings(
      await load(androidUri),
      indexUri: androidUri,
      startedAt: startedAt,
    ),
    ...await linuxFindings(
      startedAt: startedAt,
      ecosystems: ecosystems,
      packages: packages,
      query: query,
    ),
  ];
  result.sort((left, right) => left.marker.compareTo(right.marker));
  return result;
}

WatcherFinding _appleFinding(
  String releaseDate,
  Set<({String name, String url})> rawEntries,
) {
  final entries = rawEntries.toList()
    ..sort((left, right) {
      final byName = left.name.compareTo(right.name);
      return byName != 0 ? byName : left.url.compareTo(right.url);
    });
  final articleIds = <String>[
    for (final entry in entries) _appleUrl.firstMatch(entry.url)!.group(1)!,
  ];
  final digest = sha256
      .convert(utf8.encode(articleIds.join('\n')))
      .toString()
      .substring(0, 12);
  return WatcherFinding(
    watcher: 'platforms',
    marker: 'keybay-platform-apple-$releaseDate-$digest',
    title: 'Apple platform advisory triage: $releaseDate',
    subjects: <String>[for (final entry in entries) entry.name],
    references: <({String label, String url})>[
      for (final entry in entries) (label: entry.name, url: entry.url),
    ],
  );
}

DateTime _recordTime(JsonObject record) {
  final parsed = <DateTime>[];
  for (final field in <String>['published', 'modified']) {
    final value = record[field];
    if (value is String) {
      parsed.add(parseTimestamp(value));
    }
  }
  if (parsed.isEmpty) {
    throw FormatException("OSV record ${record['id']} had no timestamp");
  }
  parsed.sort();
  return parsed.last;
}

String _canonicalLinuxId(JsonObject record) {
  final candidates = <String>[];
  for (final field in <String>['aliases', 'upstream']) {
    final values = record[field] ?? const <Object?>[];
    if (values is! List) {
      throw FormatException('OSV $field was not a list');
    }
    candidates.addAll(values.whereType<String>());
  }
  final cves = candidates.where(_cve.hasMatch).toList()..sort();
  return cves.isNotEmpty ? cves.first : record['id']! as String;
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label had a non-string key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<String> _stringList(Object? value, String label) {
  if (value is! List || value.isEmpty || value.any((item) => item is! String)) {
    throw FormatException('$label must be a non-empty string list');
  }
  return value.cast<String>();
}

DateTime _parseAppleDate(String value) {
  final parts = value.split(' ');
  if (parts.length != 3 || _months[parts[1]] == null) {
    throw FormatException('unrecognized Apple release date: $value');
  }
  final day = int.tryParse(parts[0]);
  final year = int.tryParse(parts[2]);
  if (day == null || year == null) {
    throw FormatException('unrecognized Apple release date: $value');
  }
  final result = DateTime.utc(year, _months[parts[1]]!, day);
  if (result.day != day ||
      result.month != _months[parts[1]] ||
      result.year != year) {
    throw FormatException('unrecognized Apple release date: $value');
  }
  return result;
}

DateTime _parseIsoDate(String value) {
  final parsed = DateTime.tryParse('${value}T00:00:00Z');
  if (parsed == null || _dateOnly(parsed) != value) {
    throw FormatException('invalid Android bulletin date: $value');
  }
  return parsed;
}

DateTime _date(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

String _dateOnly(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _normalized(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').trim();

final class _LinuxGroup {
  final records = <String>{};
  final subjects = <String>{};
}
