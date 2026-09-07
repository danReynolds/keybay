/// Fail-closed entropy boundary for the Keybay V2 transaction engine.
library;

import 'dart:math';
import 'dart:typed_data';

import 'format/store_format.dart';

/// Largest single entropy request made through the V2 engine boundary.
///
/// The 32-byte store key is V2's largest random field. A fixed bound turns an
/// accidental large request into a programming error before allocation.
const int v2MaximumEntropyRequestBytes = V2StoreLimits.storeKeyBytes;

/// A redacted failure from the cryptographically secure random source.
final class V2EntropyFailure implements Exception {
  const V2EntropyFailure();

  @override
  String toString() => 'V2EntropyFailure';
}

/// Cryptographically secure random bytes for V2 initialization and writes.
///
/// Every successful call returns a fresh, exact-length, caller-owned mutable
/// buffer. The source retains no alias. Callers clear secret results when their
/// operation ends and never retry a failed mutation with partially generated
/// entropy.
abstract interface class V2EntropySource {
  Uint8List randomBytes(int length);
}

/// The production pure-Dart CSPRNG source.
///
/// There is no fallback to a deterministic generator. Construction or use of
/// the operating-system-backed source failing is reported as [V2EntropyFailure].
final class SecureV2EntropySource implements V2EntropySource {
  Random? _random;

  @override
  Uint8List randomBytes(int length) {
    RangeError.checkValueInInterval(
      length,
      1,
      v2MaximumEntropyRequestBytes,
      'length',
    );

    Uint8List? result;
    try {
      final random = _random ??= Random.secure();
      result = Uint8List(length);
      for (var index = 0; index < result.length; index++) {
        result[index] = random.nextInt(256);
      }
      return result;
    } on Object {
      result?.fillRange(0, result.length, 0);
      throw const V2EntropyFailure();
    }
  }
}
