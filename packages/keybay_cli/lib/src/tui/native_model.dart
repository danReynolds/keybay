import 'dart:typed_data';

import 'package:keybay/keybay.dart';

import '../application.dart' show SessionOpener;
import '../failure.dart';
import 'model.dart';
import 'store.dart';
import 'unlock_preference.dart';

// This is the CLI's hardware scope, not a website or an SDK-wide default.
const cliHardwareRpId = String.fromEnvironment(
  'keybay.hardware_rp_id',
  defaultValue: 'io.github.danreynolds.keybay.cli',
);

/// Connects the shared TUI to the native SDK. Mutable inputs reach the SDK
/// synchronously, before the model clears its borrowed buffer.
TuiModel createNativeTuiModel({
  required SessionOpener openSession,
  required Future<void> Function() resetStore,
  required void Function() authorize,
  Future<void> Function(String)? copyText,
  required void Function() onExit,
  Duration? idleTimeout = tuiIdleTimeout,
  String hardwareRpId = cliHardwareRpId,
  UnlockPreference? unlockPreference,
  Future<bool> Function(TuiCancellation)? hardwareConnected,
  Duration hardwarePollInterval = const Duration(milliseconds: 500),
  Duration hardwareConnectionTimeout = const Duration(minutes: 2),
}) => TuiModel(
  supportsHardware: true,
  unlockPreference: unlockPreference,
  hardwareConnected: hardwareConnected,
  hardwarePollInterval: hardwarePollInterval,
  hardwareConnectionTimeout: hardwareConnectionTimeout,
  openSession: ({phrase, method, pin, cancellation}) =>
      _nativeOperation(() async {
        final signal = cancellation == null ? null : PasskeyCancellation();
        if (signal != null) cancellation!.bind(signal.cancel);
        try {
          if (method?.kind == TuiAuthKind.system) {
            throw const TuiStoreException(
              'System passkeys cannot be used in this CLI.',
            );
          }
          final credential = method?.kind == TuiAuthKind.hardware
              ? PasskeyCredential.hardware(rpId: method!.rpId!, pin: pin)
              : phrase == null
              ? null
              : PassphraseCredential(phrase: phrase);
          final session = await openSession(
            credential: credential,
            methodId: credential == null ? null : method?.id,
            cancellation: signal,
          );
          return _NativeTuiSession(session, hardwareRpId);
        } finally {
          cancellation?.unbind();
        }
      }),
  resetStore: () => _nativeOperation(resetStore),
  authorize: authorize,
  copyText: copyText,
  onExit: onExit,
  idleTimeout: idleTimeout,
);

final class _NativeAuthMethod implements TuiAuthMethod {
  const _NativeAuthMethod(this.method);
  final AuthMethod method;
  @override
  String get id => method.id;
  @override
  String get label => method.label;
  @override
  TuiAuthKind get kind => switch (method) {
    PassphraseMethod() => TuiAuthKind.passphrase,
    PasskeyMethod(:final route) =>
      route == PasskeyRoute.hardware
          ? TuiAuthKind.hardware
          : TuiAuthKind.system,
  };
  @override
  String? get rpId => switch (method) {
    PasskeyMethod(:final rpId) => rpId,
    _ => null,
  };
}

Future<T> _nativeOperation<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on KeybayException catch (error) {
    final hardware = error.code == KeybayErrorCode.passkeyOperationFailed;
    throw TuiStoreException(
      hardware
          ? hardwareFailureMessage(error.passkeyCode)
          : failureForKeybay(error).lines.join('\n'),
      hardware: hardware,
      needsPin:
          error.passkeyCode == PasskeyErrorCode.pinRequired ||
          error.passkeyCode == PasskeyErrorCode.pinInvalid,
      pinRejected: error.passkeyCode == PasskeyErrorCode.pinInvalid,
      retryHardware: !const {
        PasskeyErrorCode.pinBlocked,
        PasskeyErrorCode.pinTemporarilyBlocked,
        PasskeyErrorCode.pinChangeRequired,
      }.contains(error.passkeyCode),
      methods: List.unmodifiable(error.authMethods.map(_NativeAuthMethod.new)),
      unlock: switch (error.code) {
        KeybayErrorCode.authRequired ||
        KeybayErrorCode.authMethodSelectionRequired => TuiUnlockFailure.missing,
        KeybayErrorCode.unlockFailed => TuiUnlockFailure.incorrect,
        _ => null,
      },
      canReset: const {
        KeybayErrorCode.platformKeyInvalidated,
        KeybayErrorCode.storeAuthenticationFailed,
        KeybayErrorCode.storeStateConflict,
      }.contains(error.code),
      resetIncomplete: error.code == KeybayErrorCode.resetIncomplete,
      invalidatesSession: const {
        KeybayErrorCode.staleSession,
        KeybayErrorCode.storeAuthenticationFailed,
        KeybayErrorCode.storeStateConflict,
        KeybayErrorCode.sessionClosed,
        KeybayErrorCode.storageOperationFailed,
        KeybayErrorCode.platformOperationFailed,
      }.contains(error.code),
    );
  }
}

final class _NativeTuiSession implements TuiSession {
  _NativeTuiSession(this.session, this.hardwareRpId);
  final KeybaySession session;
  final String hardwareRpId;

  @override
  bool get wasInitialized => session.wasInitialized;
  @override
  Future<List<String>> listKeys() => _nativeOperation(session.listKeys);
  @override
  Future<List<TuiAuthMethod>> listMethods() => _nativeOperation(
    () async => List.unmodifiable(
      (await session.auth.list()).map(_NativeAuthMethod.new),
    ),
  );
  @override
  Future<Uint8List?> getBytes(String key) =>
      _nativeOperation(() => session.getBytes(key));
  @override
  Future<void> setBytes(String key, Uint8List value) =>
      _nativeOperation(() => session.setBytes(key, value));
  @override
  Future<bool> delete(String key) =>
      _nativeOperation(() => session.delete(key));
  @override
  Future<void> clearAll() => _nativeOperation(session.clearAll);
  @override
  Future<void> addPassphrase(Uint8List phrase) => _nativeOperation(() async {
    await session.auth.add(PassphraseCredential(phrase: phrase));
  });
  @override
  Future<void> addHardwareKey({
    required String label,
    Uint8List? pin,
    required TuiCancellation cancellation,
  }) => _nativeOperation(() async {
    final signal = PasskeyCancellation();
    cancellation.bind(signal.cancel);
    try {
      await session.auth.add(
        PasskeyCredential.hardware(
          rpId: hardwareRpId,
          displayName: 'Keybay',
          pin: pin,
        ),
        label: label,
        cancellation: signal,
      );
    } finally {
      cancellation.unbind();
    }
  });
  @override
  Future<void> removeMethod(TuiAuthMethod method) => _nativeOperation(() async {
    if (method is! _NativeAuthMethod) {
      throw const TuiStoreException(
        'This unlock method is no longer available.',
      );
    }
    final survivors = (await session.auth.list())
        .where((m) => m.id != method.id)
        .toList();
    if (survivors.isNotEmpty &&
        survivors.every(
          (m) => m is PasskeyMethod && m.route == PasskeyRoute.system,
        )) {
      throw const TuiStoreException(
        'This TUI cannot unlock the remaining passkeys. Remove this method using a build that supports them.',
      );
    }
    await session.auth.remove(method.method);
  });
  @override
  Future<void> close() => _nativeOperation(session.close);
}
