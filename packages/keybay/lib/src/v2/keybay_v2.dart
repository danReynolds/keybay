/// Public Keybay V2 contract and production runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'android_host_platform.dart';
import 'apple_data_protection_host_platform.dart';
import 'application_identity.dart';
import 'entropy_source.dart';
import 'format/store_crypto.dart';
import 'format/store_format.dart';
import 'host_platform.dart';
import 'linux_host_platform.dart';
import 'macos_host_platform.dart';
import 'platform_protector.dart';
import 'store_files.dart';

part 'framed_store_reader.dart';
part 'framed_store_rotation.dart';
part 'framed_store_writer.dart';
part 'passphrase_kdf.dart';

/// Opens the one Keybay store belonging to the current host application.
///
/// The runtime selects only a qualified platform profile. It never probes V1
/// state, migrates prior storage, or falls back to process memory.
abstract final class Keybay {
  /// Opens or initializes the current application's store.
  /// Trusted operating-system/provider UI may participate in unlocking it.
  static Future<KeybaySession> open({KeybayCredential? credential}) =>
      _withCredential(credential, _productionRuntime._open);

  /// Removes the encrypted store and resets Keybay-owned provider state.
  /// Nonsecret coordination files and provider-owned roots may remain.
  /// Trusted operating-system/provider UI may participate in this operation.
  static Future<void> reset() => _future(_productionRuntime.reset);
}

/// Public limits callers may need before submitting plaintext to Keybay.
abstract final class KeybayLimits {
  /// Maximum UTF-8 or binary size of one record value.
  static const int recordValueBytes = V2StoreLimits.recordValueBytes;
}

/// Authentication material supplied to an operation.
///
/// Credential objects borrow caller-owned bytes. Receiving operations snapshot
/// those bytes synchronously and clear their own copy when the operation ends.
sealed class KeybayCredential {
  KeybayCredential();
}

/// A caller-owned passphrase byte buffer.
final class PassphraseCredential extends KeybayCredential {
  /// Creates a borrowed passphrase view without copying [phrase].
  PassphraseCredential({required Uint8List phrase}) : _phrase = phrase;

  final Uint8List _phrase;

  @override
  String toString() => 'PassphraseCredential(<redacted>)';
}

/// Stable machine-readable Keybay V2 failures.
enum KeybayErrorCode {
  applicationIdentityUnavailable,
  platformProtectorUnavailable,
  platformProtectorLocked,
  platformInteractionRequired,
  platformOperationFailed,
  platformKeyInvalidated,
  storageOperationFailed,
  entropyUnavailable,
  authRequired,
  protectionMismatch,
  unlockFailed,
  authMethodAlreadyConfigured,
  authMethodNotConfigured,
  resetIncomplete,
  storeAuthenticationFailed,
  unsupportedStoreVersion,
  storeStateConflict,
  storeBusy,
  staleSession,
  sessionClosed,
  invalidRecordKey,
  invalidRecordEncoding,
  limitExceeded,
  invalidAuthInput,
}

/// A redacted Keybay V2 operation failure.
final class KeybayException implements Exception {
  KeybayException._(this.code, this.message);

  /// Stable failure code. Branch on this rather than [message].
  final KeybayErrorCode code;

  /// Human-readable, redacted detail.
  final String message;

  @override
  String toString() => 'KeybayException(${code.name})';
}

/// A configured additional unlock method.
sealed class AuthMethod {
  const AuthMethod._(this.id);

  /// Opaque stable identifier used to remove this configured method.
  final String id;
}

/// A configured singleton passphrase method.
final class PassphraseMethod extends AuthMethod {
  const PassphraseMethod._(super.id) : super._();

  @override
  String toString() => 'PassphraseMethod(id: $id)';
}

/// An authenticated, explicitly closable handle to the application store.
///
/// Record operations never present provider UI, including when diagnosing a
/// stale or damaged store. Only unlock-method changes may request provider UI.
abstract interface class KeybaySession {
  /// Whether this open call initialized previously absent state.
  bool get wasInitialized;

  /// True from the instant closing starts.
  bool get isClosed;

  /// Additional unlock-method management for this authenticated session.
  KeybayAuthManager get auth;

  Future<String?> get(String key);

  Future<void> set(String key, String value);

  Future<Uint8List?> getBytes(String key);

  Future<Map<String, Uint8List?>> getManyBytes(Iterable<String> keys);

  /// Returns the authenticated record names in canonical order.
  ///
  /// This decrypts the store manifest but no record value. The returned list
  /// is immutable and contains caller-owned Dart strings.
  Future<List<String>> listKeys();

  Future<void> setBytes(String key, Uint8List value);

  Future<bool> contains(String key);

  Future<bool> delete(String key);

  Future<void> clearAll();

  Future<void> close();
}

/// Additional unlock-method management for an authenticated session.
abstract interface class KeybayAuthManager {
  /// Lists the authenticated unlock policy without presenting provider UI.
  Future<List<AuthMethod>> list();

  /// Adds an unlock method; trusted operating-system/provider UI is permitted.
  Future<AuthMethod> add(KeybayCredential credential);

  /// Updates an unlock method; trusted operating-system/provider UI is permitted.
  Future<AuthMethod> update(KeybayCredential replacement);

  /// Removes an unlock method; trusted operating-system/provider UI is permitted.
  Future<void> remove(String id);
}

enum _SessionLifecycle { open, closing, closed }

final _productionRuntime = V2StoreEngine(switch (Platform.operatingSystem) {
  'android' => AndroidHostPlatform(),
  'ios' => IOSHostPlatform(),
  'linux' => LinuxHostPlatform(),
  'macos' => MacOSHostPlatform(),
  _ => const UnsupportedHostPlatform(),
});

final class _CredentialSnapshot {
  _CredentialSnapshot.passphrase(this.bytes);

  final Uint8List bytes;

  void clear() => _clear(bytes);
}

Future<T> _withCredential<T>(
  KeybayCredential? credential,
  Future<T> Function(_CredentialSnapshot? credential) operation,
) {
  _CredentialSnapshot? snapshot;
  try {
    snapshot = _snapshotCredential(credential);
    final future = operation(snapshot);
    return future.whenComplete(() => snapshot?.clear());
  } on Object catch (error, stackTrace) {
    snapshot?.clear();
    return Future<T>.error(error, stackTrace);
  }
}

_CredentialSnapshot? _snapshotCredential(KeybayCredential? credential) {
  if (credential == null) return null;
  return switch (credential) {
    PassphraseCredential() => _snapshotPassphrase(credential._phrase),
  };
}

_CredentialSnapshot _snapshotPassphrase(Uint8List phrase) {
  if (phrase.isEmpty || phrase.length > 1024) {
    throw _error(
      KeybayErrorCode.invalidAuthInput,
      'A passphrase must contain between 1 and 1024 bytes.',
    );
  }
  return _CredentialSnapshot.passphrase(Uint8List.fromList(phrase));
}

Future<T> _future<T>(FutureOr<T> Function() operation) {
  try {
    return Future<T>.sync(operation);
  } on Object catch (error, stackTrace) {
    return Future<T>.error(error, stackTrace);
  }
}

KeybayException _error(KeybayErrorCode code, String message) =>
    KeybayException._(code, message);

void _validateRecordKey(String key) {
  if (!isValidV2RecordKey(key)) {
    throw _error(
      KeybayErrorCode.invalidRecordKey,
      'Record keys must use the canonical Keybay key grammar.',
    );
  }
}

void _validateRecordValueLength(int length) {
  if (length < 0 || length > V2StoreLimits.recordValueBytes) {
    throw _error(
      KeybayErrorCode.limitExceeded,
      'The record value limit was exceeded.',
    );
  }
}

void _validateRecordString(String value) {
  // Every UTF-16 code unit requires at least one UTF-8 byte. Rejecting this
  // first keeps the validation walk and the later encoding allocation bounded.
  if (value.length > V2StoreLimits.recordValueBytes) {
    _validateRecordValueLength(value.length);
  }

  var utf8Length = 0;
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit <= 0x7f) {
      utf8Length += 1;
    } else if (codeUnit <= 0x7ff) {
      utf8Length += 2;
    } else if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      if (++index == value.length) _invalidRecordString();
      final trailing = value.codeUnitAt(index);
      if (trailing < 0xdc00 || trailing > 0xdfff) {
        _invalidRecordString();
      }
      utf8Length += 4;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      _invalidRecordString();
    } else {
      utf8Length += 3;
    }

    if (utf8Length > V2StoreLimits.recordValueBytes) {
      _validateRecordValueLength(utf8Length);
    }
  }
}

Never _invalidRecordString() => throw _error(
  KeybayErrorCode.invalidRecordEncoding,
  'Record string values must contain valid Unicode.',
);

void _clear(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}

bool _constantTimeEquals(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}
