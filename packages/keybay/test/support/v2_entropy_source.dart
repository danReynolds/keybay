import 'dart:collection';
import 'dart:typed_data';

import 'package:keybay/src/v2/entropy_source.dart';

/// A disposable deterministic entropy source for V2 engine tests.
///
/// Never supply real secrets. Scripted buffers are copied at construction,
/// transferred to the caller one at a time, and cleared if still queued when
/// [dispose] is called.
final class ScriptedV2EntropySource implements V2EntropySource {
  ScriptedV2EntropySource(Iterable<List<int>> responses)
    : _responses = Queue<Uint8List>.of(responses.map(Uint8List.fromList));

  final Queue<Uint8List> _responses;
  Exception? nextFailure;
  int requestCount = 0;
  bool _disposed = false;

  @override
  Uint8List randomBytes(int length) {
    if (_disposed) throw StateError('The entropy source is disposed.');
    requestCount++;

    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      throw failure;
    }
    if (_responses.isEmpty) {
      throw StateError('No scripted entropy response remains.');
    }

    final response = _responses.removeFirst();
    if (response.length != length) {
      response.fillRange(0, response.length, 0);
      throw StateError('The scripted entropy length does not match.');
    }
    return response;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final response in _responses) {
      response.fillRange(0, response.length, 0);
    }
    _responses.clear();
  }
}
