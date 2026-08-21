import '../finding.dart';
import '../http.dart' as http;

typedef LatestVersionLookup = Future<String> Function(String name);

final _package = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
final _version = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$');

Future<String> pubLatest(String name) async {
  final payload = await http.fetchJson(
    Uri.parse('https://pub.dev/api/packages/$name'),
  );
  final root = _object(payload, 'pub.dev response');
  final latest = _object(root['latest'], 'pub.dev latest release');
  final version = latest['version'];
  if (version is! String || !_version.hasMatch(version)) {
    throw FormatException('pub.dev returned an unsafe version: $version');
  }
  return version;
}

Future<List<WatcherFinding>> criticalFindings(
  Map<String, Object?> config, {
  LatestVersionLookup? latestVersion,
}) async {
  final lookup = latestVersion ?? pubLatest;
  final rawPackages = config['packages'];
  if (rawPackages is! List || rawPackages.isEmpty) {
    throw const FormatException(
      'critical watcher needs a non-empty packages list',
    );
  }
  final result = <WatcherFinding>[];
  for (final rawPackage in rawPackages) {
    final package = _object(rawPackage, 'critical package definition');
    final ecosystem = package['ecosystem'];
    final name = package['name'];
    final reviewed = package['reviewed_version'];
    final url = package['url'];
    if (ecosystem != 'Pub' || name is! String || !_package.hasMatch(name)) {
      throw FormatException('unsupported critical package: $package');
    }
    if (reviewed is! String || !_version.hasMatch(reviewed)) {
      throw FormatException('invalid reviewed version for $name');
    }
    if (url != 'https://pub.dev/packages/$name') {
      throw FormatException('invalid package URL for $name');
    }
    final latest = await lookup(name);
    if (!_version.hasMatch(latest)) {
      throw FormatException('pub.dev returned an unsafe version: $latest');
    }
    if (latest == reviewed) {
      continue;
    }
    final markerVersion = latest.replaceAll(RegExp(r'[^0-9A-Za-z_.-]'), '-');
    result.add(
      WatcherFinding(
        watcher: 'critical',
        marker: 'keybay-critical-pub-$name-$markerVersion',
        title: 'Critical dependency review: $name $latest',
        subjects: <String>[
          'Pub/$name: reviewed $reviewed; published $latest',
        ],
        references: <({String label, String url})>[
          (label: 'Pub/$name', url: url as String),
        ],
      ),
    );
  }
  return result;
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
