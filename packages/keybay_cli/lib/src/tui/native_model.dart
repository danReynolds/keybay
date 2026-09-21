import 'dart:typed_data';

import 'package:keybay/keybay.dart';

import '../application.dart' show SessionOpener;
import '../failure.dart';
import 'model.dart';
import 'store.dart';

/// Connects the shared TUI to the native SDK without changing credential
/// ownership: SDK calls snapshot borrowed bytes before control returns.
TuiModel createNativeTuiModel({
  required SessionOpener openSession,
  required Future<void> Function() resetStore,
  required void Function() authorize,
  Future<void> Function(String)? copyText,
  required void Function() onExit,
  Duration? idleTimeout = tuiIdleTimeout,
}) => TuiModel(
  openSession: ({phrase}) => _nativeOperation(() async {
    final session = await openSession(
      credential: phrase == null ? null : PassphraseCredential(phrase: phrase),
    );
    return _NativeTuiSession(session);
  }),
  resetStore: () => _nativeOperation(resetStore),
  authorize: authorize,
  copyText: copyText,
  onExit: onExit,
  idleTimeout: idleTimeout,
);

Future<T> _nativeOperation<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on KeybayException catch (error) {
    throw TuiStoreException(
      failureForKeybay(error).lines.join('\n'),
      unlock: switch (error.code) {
        KeybayErrorCode.authRequired => TuiUnlockFailure.missing,
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
  _NativeTuiSession(this.session);
  final KeybaySession session;

  @override
  bool get wasInitialized => session.wasInitialized;
  @override
  Future<List<String>> listKeys() => _nativeOperation(session.listKeys);
  @override
  Future<String?> passphraseId() => _nativeOperation(
    () async => (await session.auth.list())
        .whereType<PassphraseMethod>()
        .firstOrNull
        ?.id,
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
  Future<void> changePassphrase(Uint8List phrase, {required bool replacing}) =>
      _nativeOperation(() async {
        final credential = PassphraseCredential(phrase: phrase);
        if (replacing) {
          await session.auth.update(credential);
        } else {
          await session.auth.add(credential);
        }
      });
  @override
  Future<void> removePassphrase(String id) =>
      _nativeOperation(() => session.auth.remove(id));
  @override
  Future<void> close() => _nativeOperation(session.close);
}
