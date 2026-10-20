/// Public Keybay V2 contract and production runtime.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:keypass/keypass.dart';

import '../process_hardening.dart';
import 'android_host_platform.dart';
import 'apple_data_protection_host_platform.dart';
import 'application_identity.dart';
import 'entropy_source.dart';
import 'format/method_crypto.dart';
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
part 'passkey_credential.dart';
part 'auth_methods.dart';
part 'auth_metadata_commit.dart';

/// Opens the one Keybay store belonging to the current host application.
///
/// The runtime selects only a qualified platform profile. It never probes V1
/// state, migrates prior storage, or falls back to process memory.
abstract final class Keybay {
  /// Opens the current application's store.
  ///
  /// Without a credential, fully absent state is initialized platform-only.
  /// A supplied credential only authenticates an existing store; it never
  /// enrolls a method. If the encrypted file is absent, returns
  /// [KeybayErrorCode.storeNotFound].
  /// Enroll protection explicitly with [KeybayAuthManager.add] before writing
  /// records that should require it.
  /// Trusted operating-system/provider UI may participate in unlocking it.
  /// [methodId] selects an enrollment when several match the credential.
  /// [cancellation] cancels a passkey attempt; await the operation to settle.
  ///
  /// Before anything else, it applies Keybay's process hardening; see
  /// [processHardening].
  static Future<KeybaySession> open({
    KeybayCredential? credential,
    String? methodId,
    PasskeyCancellation? cancellation,
  }) {
    applyProcessHardening();
    return _withCredential(
      credential,
      _productionRuntime._open,
      methodId: methodId,
      cancellation: cancellation,
    );
  }

  /// Removes the encrypted store and resets Keybay-owned provider state.
  /// Nonsecret coordination files and provider-owned roots may remain.
  /// Trusted operating-system/provider UI may participate in this operation.
  static Future<void> reset() => _future(_productionRuntime.reset);

  /// What Keybay's process hardening applied, and why anything was not.
  ///
  /// Keybay hardens the process automatically at every [open], before any
  /// secret loads, so applications need not call anything. Reading this
  /// status also applies it, so an application that collects a passphrase or
  /// PIN before opening can read it first in `main` to harden earlier.
  ///
  /// In release and profile builds on Linux the process becomes non-dumpable
  /// (`PR_SET_DUMPABLE` 0) and its soft `RLIMIT_CORE` becomes 0: a crash
  /// writes no core file, and other programs running as the same user can
  /// neither attach a debugger nor read `/proc/<pid>/mem`. On macOS the soft
  /// `RLIMIT_CORE` becomes 0. Debug builds set only the core-file limit, so
  /// development debuggers keep working. iOS and Android are unchanged.
  ///
  /// A failure is reported here, never fatal and never replaced by a weaker
  /// policy: check [KeybayProcessHardening.failed] and decide what to hold.
  /// On Linux the debugger protection fails when a tracer is already
  /// attached, and in a user namespace such as Flatpak's, whose owner keeps
  /// ptrace access from outside it. Hardening does not protect against root
  /// or the kernel, against code injected at launch through a launcher,
  /// shell startup files or a per-user install, or before it first runs.
  ///
  /// A build can turn it off with
  /// `--dart-define=keybay.process_hardening=false`, which leaves core files
  /// and same-user debuggers able to read the secrets this process holds.
  static KeybayProcessHardening get processHardening => applyProcessHardening();
}

/// Public limits callers may need before submitting plaintext to Keybay.
abstract final class KeybayLimits {
  /// Maximum UTF-8 or binary size of one record value.
  static const int recordValueBytes = V2StoreLimits.recordValueBytes;
}

/// Authentication material supplied to an operation.
///
/// Passphrases and hardware PINs borrow caller-owned bytes; operations snapshot
/// those bytes synchronously and clear their own copy. Passkeys acquire
/// temporary encryption material only during an authentication operation.
sealed class KeybayCredential {
  const KeybayCredential();
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
///
/// Branch on these codes, never on [KeybayException.message]. None of them is
/// permission to delete or reset a store automatically.
enum KeybayErrorCode {
  /// The host application's identity could not be established, such as a
  /// desktop Dart program without a declared `keybay: application_id`.
  applicationIdentityUnavailable,

  /// No qualified platform protector exists on this host. Keybay does not
  /// fall back to weaker storage.
  platformProtectorUnavailable,

  /// The platform key store is locked, such as a locked Linux keyring.
  /// Unlock it and retry.
  platformProtectorLocked,

  /// The platform key store needs user interaction this context cannot show.
  /// Retry from an attended session.
  platformInteractionRequired,

  /// A platform key store operation failed. A submitted change may have
  /// committed; reopen to inspect state before retrying.
  platformOperationFailed,

  /// The platform key that protects the store no longer exists or can no
  /// longer be used. Existing values cannot be recovered without it.
  platformKeyInvalidated,

  /// Reading or writing the store files failed. A submitted change may have
  /// committed; reopen to inspect state before retrying.
  storageOperationFailed,

  /// A credential-based open found no encrypted store, and nothing was
  /// created. Offer explicit first-use setup rather than opening without a
  /// credential automatically, which creates a new platform-only store.
  storeNotFound,

  /// Secure random bytes were unavailable.
  entropyUnavailable,

  /// The store has additional protection and the call supplied no
  /// credential. [KeybayException.authMethods] lists the configured methods.
  authRequired,

  /// The supplied credential or route does not match the store's protection,
  /// such as a passphrase for a store protected only by passkeys.
  protectionMismatch,

  /// The supplied credential did not unlock the store, such as a wrong
  /// passphrase.
  unlockFailed,

  /// The method cannot be added because an equivalent one exists; a store
  /// allows at most one passphrase.
  authMethodAlreadyConfigured,

  /// The method is not configured in this store, including a method from
  /// another store or one already removed.
  authMethodNotConfigured,

  /// Several configured passkeys match the credential. Retry with a
  /// `methodId` from [KeybayException.authMethods].
  authMethodSelectionRequired,

  /// A passkey operation failed. [KeybayException.passkeyCode] says why, such
  /// as cancellation, a PIN error or a missing credential.
  passkeyOperationFailed,

  /// A reset passed the point where the store's files are revoked but did not
  /// finish. Call [Keybay.reset] again to complete it.
  resetIncomplete,

  /// The store failed authentication: it was damaged, replaced, or changed by
  /// another process during this session. Close and reopen; do not erase it.
  storeAuthenticationFailed,

  /// The store uses a format this Keybay version cannot open, such as a
  /// 0.2.0 store with a passphrase or passkey. Nothing was changed.
  unsupportedStoreVersion,

  /// The store files and platform state disagree, so Keybay can neither open
  /// nor initialize them safely. Investigate before any deliberate reset.
  storeStateConflict,

  /// Another Keybay operation holds the store: retry with bounded backoff.
  /// Also reported for a call made from inside an authentication callback,
  /// which must instead run after the callback returns.
  storeBusy,

  /// This session no longer matches the store, such as after a reset or a
  /// protection change elsewhere. Close it and open a new one.
  staleSession,

  /// The session is closed or closing. Open a new one.
  sessionClosed,

  /// The record key does not follow Keybay's key format: 1 to 120 ASCII
  /// characters in slash-separated segments of letters, digits, `.`, `_` and
  /// `-`, each starting with a letter or digit.
  invalidRecordKey,

  /// A string value is not valid Unicode, or a stored value read with
  /// [KeybaySession.get] is not valid UTF-8. Use [KeybaySession.getBytes] for
  /// binary values.
  invalidRecordEncoding,

  /// A size or count limit was exceeded, such as [KeybayLimits.recordValueBytes].
  limitExceeded,

  /// The supplied credential input is invalid, such as an empty passphrase or
  /// a malformed passkey request.
  invalidAuthInput,
}

/// A redacted Keybay V2 operation failure.
final class KeybayException implements Exception {
  KeybayException._(
    this.code,
    this.message, {
    this.passkeyCode,
    List<AuthMethod> authMethods = const [],
  }) : authMethods = List.unmodifiable(authMethods);

  /// Stable failure code. Branch on this rather than [message].
  final KeybayErrorCode code;

  /// Human-readable, redacted detail.
  final String message;

  /// Redacted Keypass failure detail, when [code] is passkeyOperationFailed.
  final PasskeyErrorCode? passkeyCode;

  /// Available-method hints for authRequired/selection-required failures.
  /// The platform package has authenticated these hints, but full store
  /// authentication still requires successfully unlocking a method.
  final List<AuthMethod> authMethods;

  @override
  String toString() => 'KeybayException(${code.name})';
}

/// A configured additional unlock method.
sealed class AuthMethod {
  const AuthMethod._(this.id, this._storeId, {required this.label});

  /// Opaque stable identifier used to select this method when opening a store.
  /// Pass the method object itself to [KeybayAuthManager.remove].
  final String id;

  /// Human-readable enrollment name. It is not used to select a credential.
  final String label;

  // Bind descriptors to their originating vault, including across reset.
  final String _storeId;
}

/// A configured singleton passphrase method.
final class PassphraseMethod extends AuthMethod {
  const PassphraseMethod._(
    super.id,
    super.storeId, {
    super.label = 'Passphrase',
  }) : super._();

  @override
  String toString() => 'PassphraseMethod(id: $id)';
}

/// An authenticated, explicitly closable handle to the application store.
///
/// Record operations never acquire a provider, including on failure. A peer
/// process's protection change may report [KeybayErrorCode.storeAuthenticationFailed]
/// rather than [KeybayErrorCode.staleSession]; close and authenticate again.
/// Only unlock-method changes may request provider UI.
abstract interface class KeybaySession {
  /// Whether this open call initialized previously absent state.
  bool get wasInitialized;

  /// True from the instant closing starts.
  bool get isClosed;

  /// Additional unlock-method management for this authenticated session.
  KeybayAuthManager get auth;

  /// Returns the value stored under [key] as a string, or null if absent.
  ///
  /// Fails with [KeybayErrorCode.invalidRecordEncoding] if the stored value is
  /// not valid UTF-8; read binary values with [getBytes].
  Future<String?> get(String key);

  /// Stores [value] under [key], replacing any existing value.
  ///
  /// The UTF-8 encoding of [value] may be up to
  /// [KeybayLimits.recordValueBytes].
  Future<void> set(String key, String value);

  /// Returns the bytes stored under [key], or null if absent.
  ///
  /// The returned buffer belongs to the caller; clear it when done.
  Future<Uint8List?> getBytes(String key);

  /// Returns the bytes stored under each of [keys], with null for absent keys.
  ///
  /// Reads up to 1,024 keys and 16 MiB of values in one authenticated pass.
  /// The returned buffers belong to the caller.
  Future<Map<String, Uint8List?>> getManyBytes(Iterable<String> keys);

  /// Returns the authenticated record names in canonical order.
  ///
  /// This decrypts the store manifest but no record value. The returned list
  /// is immutable and contains caller-owned Dart strings.
  Future<List<String>> listKeys();

  /// Stores a copy of [value] under [key], replacing any existing value.
  ///
  /// [value] may be up to [KeybayLimits.recordValueBytes]. Keybay copies it
  /// synchronously, so the caller may clear its buffer afterwards.
  Future<void> setBytes(String key, Uint8List value);

  /// Whether a value is stored under [key], without decrypting the value.
  Future<bool> contains(String key);

  /// Removes the value stored under [key]. Returns whether one was removed.
  Future<bool> delete(String key);

  /// Removes every record while keeping the store and its protection.
  Future<void> clearAll();

  /// Closes the session after its in-flight operations settle, then clears
  /// its key material. Safe to call more than once.
  Future<void> close();
}

/// Additional unlock-method management for an authenticated session.
abstract interface class KeybayAuthManager {
  /// Lists the authenticated unlock policy without presenting provider UI.
  Future<List<AuthMethod>> list();

  /// Adds an alternative unlock method; provider UI is permitted.
  ///
  /// At most one passphrase is allowed; adding a second fails with
  /// [KeybayErrorCode.authMethodAlreadyConfigured]. Multiple passkeys may share
  /// an RP ID and route. Adding never replaces an existing method.
  /// [label] names this enrollment. [cancellation] applies to passkey attempts.
  Future<AuthMethod> add(
    KeybayCredential credential, {
    String? label,
    PasskeyCancellation? cancellation,
  });

  /// Removes a method returned by [add] or [list]; provider UI is permitted.
  ///
  /// Removing the final method returns to platform-only protection. Removing a
  /// passkey method does not delete the credential from its provider.
  /// Foreign-vault and already removed methods fail with
  /// [KeybayErrorCode.authMethodNotConfigured]. Removing and adding are separate
  /// commits; changing a passphrase requires removing the existing one first.
  Future<void> remove(AuthMethod method);
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
  _CredentialSnapshot({
    required this.bytes,
    this.passkey,
    this.methodId,
    required this.label,
    this.cancellation,
  });

  final Uint8List bytes;
  final PasskeyCredential? passkey;
  final String? methodId;
  final String label;
  final PasskeyCancellation? cancellation;

  void clear() => _clear(bytes);
}

Future<T> _withCredential<T>(
  KeybayCredential? credential,
  Future<T> Function(_CredentialSnapshot? credential) operation, {
  String? methodId,
  PasskeyCancellation? cancellation,
}) {
  _CredentialSnapshot? snapshot;
  try {
    _checkAuthCallback();
    snapshot = _snapshotCredential(
      credential,
      methodId: methodId,
      cancellation: cancellation,
    );
    final future = operation(snapshot);
    return future.whenComplete(() => snapshot?.clear());
  } on Object catch (error, stackTrace) {
    snapshot?.clear();
    return Future<T>.error(error, stackTrace);
  }
}

_CredentialSnapshot? _snapshotCredential(
  KeybayCredential? credential, {
  String? methodId,
  String? label,
  PasskeyCancellation? cancellation,
}) {
  if (credential == null) {
    if (methodId != null || cancellation != null) {
      throw _error(
        KeybayErrorCode.invalidAuthInput,
        'A credential is required.',
      );
    }
    return null;
  }
  if (cancellation != null && credential is! PasskeyCredential) {
    throw _error(
      KeybayErrorCode.invalidAuthInput,
      'Cancellation applies to passkey operations.',
    );
  }
  final name =
      label ??
      (credential is PasskeyCredential ? 'Keybay vault' : 'Passphrase');
  try {
    if (methodId != null) decodeMethodId(methodId);
    final encoded = utf8.encode(name);
    if (name.trim().isEmpty ||
        encoded.length > v2MaxMethodLabelBytes ||
        utf8.decode(encoded) != name) {
      throw const FormatException();
    }
  } on Object {
    throw _error(
      KeybayErrorCode.invalidAuthInput,
      'Invalid authentication metadata.',
    );
  }
  final Uint8List bytes;
  PasskeyCredential? passkey;
  switch (credential) {
    case PassphraseCredential():
      final phrase = credential._phrase;
      if (phrase.isEmpty || phrase.length > 1024) {
        throw _error(
          KeybayErrorCode.invalidAuthInput,
          'A passphrase must contain between 1 and 1024 bytes.',
        );
      }
      bytes = Uint8List.fromList(phrase);
    case PasskeyCredential():
      passkey = _snapshotPasskey(credential);
      bytes = passkey._pin ?? Uint8List(0);
  }
  return _CredentialSnapshot(
    bytes: bytes,
    passkey: passkey,
    methodId: methodId,
    label: name,
    cancellation: cancellation,
  );
}

Future<T> _future<T>(FutureOr<T> Function() operation) {
  try {
    _checkAuthCallback();
    return Future<T>.sync(operation);
  } on Object catch (error, stackTrace) {
    return Future<T>.error(error, stackTrace);
  }
}

KeybayException _error(
  KeybayErrorCode code,
  String message, {
  PasskeyErrorCode? passkeyCode,
  List<AuthMethod> authMethods = const [],
}) => KeybayException._(
  code,
  message,
  passkeyCode: passkeyCode,
  authMethods: authMethods,
);

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
