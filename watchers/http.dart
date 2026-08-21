import 'dart:convert';
import 'dart:io';

const _timeout = Duration(seconds: 30);
const _maximumResponseBytes = 8 * 1024 * 1024;
const _userAgent = 'keybay-security-watchers/1';

Future<String> fetchText(Uri uri) => _request(uri);

Future<Object?> fetchJson(Uri uri) async {
  final text = await _request(uri);
  try {
    return jsonDecode(text);
  } on FormatException catch (error) {
    throw FormatException('non-JSON response from $uri: $error');
  }
}

Future<Object?> postJson(Uri uri, Object body) async {
  final text = await _request(uri, body: jsonEncode(body));
  try {
    return jsonDecode(text);
  } on FormatException catch (error) {
    throw FormatException('non-JSON response from $uri: $error');
  }
}

Future<String> _request(Uri uri, {String? body}) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final request =
        await (body == null ? client.getUrl(uri) : client.postUrl(uri))
            .timeout(_timeout);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(body);
    }
    final response = await request.close().timeout(_timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'unexpected HTTP ${response.statusCode} from $uri',
        uri: uri,
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(_timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maximumResponseBytes) {
        throw HttpException('response from $uri was too large', uri: uri);
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error) {
      throw FormatException('non-UTF-8 response from $uri: $error');
    }
  } finally {
    client.close(force: true);
  }
}
