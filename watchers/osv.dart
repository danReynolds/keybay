import 'http.dart' as http;

typedef JsonObject = Map<String, Object?>;
typedef OsvPoster = Future<Object?> Function(JsonObject body);
typedef OsvQuery = Future<List<JsonObject>> Function(
  String ecosystem,
  String name,
);

final _advisoryId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$');
final _endpoint = Uri.parse('https://api.osv.dev/v1/query');

bool isSafeAdvisoryId(String value) => _advisoryId.hasMatch(value);

Future<List<JsonObject>> queryPackage(
  String ecosystem,
  String name, {
  OsvPoster? post,
}) async {
  final send = post ?? (body) => http.postJson(_endpoint, body);
  final records = <JsonObject>[];
  String? pageToken;
  while (true) {
    final query = <String, Object?>{
      'package': <String, String>{'name': name, 'ecosystem': ecosystem},
      if (pageToken != null) 'page_token': pageToken,
    };
    final payload = _object(await send(query), 'OSV response');
    final rawVulnerabilities = payload['vulns'] ?? const <Object?>[];
    if (rawVulnerabilities is! List) {
      throw const FormatException('OSV vulnerabilities was not a list');
    }
    for (final rawVulnerability in rawVulnerabilities) {
      final vulnerability = _object(
        rawVulnerability,
        'OSV vulnerability',
      );
      final id = vulnerability['id'];
      if (id is! String || !isSafeAdvisoryId(id)) {
        throw FormatException('OSV returned an unsafe advisory ID: $id');
      }
      records.add(vulnerability);
    }
    final rawPageToken = payload['next_page_token'];
    if (rawPageToken == null || rawPageToken == '') {
      return records;
    }
    if (rawPageToken is! String || rawPageToken.length > 4096) {
      throw const FormatException('OSV returned an invalid page token');
    }
    pageToken = rawPageToken;
  }
}

JsonObject _object(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label was not an object');
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
