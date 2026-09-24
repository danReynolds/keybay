import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:keybay/keybay.dart';

import 'vault_backend.dart';

enum VaultStage {
  /// Opening the store.
  opening,

  /// Open: records can be listed, read and changed.
  open,

  /// A passphrase is needed to open the store.
  locked,

  /// Closed by the user or because the app left the foreground.
  closed,

  /// The store could not be opened; see [Vault.message].
  failed,
}

/// The app's view of its one Keybay store: whether it is open, which record
/// names it holds and how it is protected. Values are read on demand and never
/// cached here.
final class Vault extends ChangeNotifier {
  Vault(this._backend);

  final VaultBackend _backend;
  KeybaySession? _session;

  /// Incremented by every open, close and reset, so a slower operation that
  /// was superseded cannot install its session or state afterwards.
  int _generation = 0;

  VaultStage stage = VaultStage.opening;
  List<String> keys = const [];
  bool passphraseProtected = false;

  /// Whether the last open created a new, empty store.
  bool createdNewStore = false;

  /// A short, user-facing explanation of the last failure.
  String? message;

  Future<void> open() async {
    final generation = ++_generation;
    await _closeSession();
    _enter(VaultStage.opening);
    try {
      final session = await _backend.open();
      if (generation != _generation) return session.close();
      await _adopt(session, generation);
    } on KeybayException catch (error) {
      if (generation != _generation) return;
      if (error.code == KeybayErrorCode.authRequired) {
        _enter(VaultStage.locked);
      } else {
        _enter(VaultStage.failed, describe(error.code));
      }
    }
  }

  /// Opens a passphrase-protected store. Returns false if it stays locked.
  Future<bool> unlock(String passphrase) async {
    final generation = ++_generation;
    final phrase = _utf8(passphrase);
    try {
      final session = await _backend.open(
        credential: PassphraseCredential(phrase: phrase),
      );
      if (generation != _generation) {
        await session.close();
        return false;
      }
      await _adopt(session, generation);
      return stage == VaultStage.open;
    } on KeybayException catch (error) {
      if (generation != _generation) return false;
      if (error.code == KeybayErrorCode.unlockFailed ||
          error.code == KeybayErrorCode.invalidAuthInput) {
        _enter(VaultStage.locked, describe(error.code));
      } else {
        _enter(VaultStage.failed, describe(error.code));
      }
      return false;
    } finally {
      // The credential borrows this buffer; the SDK is done with it once the
      // open completes.
      phrase.fillRange(0, phrase.length, 0);
    }
  }

  Future<String?> read(String key) =>
      _withSession((session) => session.get(key));

  Future<void> save(String key, String value) => _withSession((session) async {
    await session.set(key, value);
    await _refresh(session);
  });

  Future<void> remove(String key) => _withSession((session) async {
    await session.delete(key);
    await _refresh(session);
  });

  /// Adds a passphrase, or replaces the current one.
  Future<void> setPassphrase(String passphrase) =>
      _withSession((session) async {
        final phrase = _utf8(passphrase);
        try {
          final credential = PassphraseCredential(phrase: phrase);
          if (passphraseProtected) {
            await session.auth.update(credential);
          } else {
            await session.auth.add(credential);
          }
        } finally {
          phrase.fillRange(0, phrase.length, 0);
        }
        await _refresh(session);
      });

  Future<void> removePassphrase() => _withSession((session) async {
    for (final method in await session.auth.list()) {
      if (method is PassphraseMethod) await session.auth.remove(method.id);
    }
    await _refresh(session);
  });

  /// Closes the session. The store stays on the device.
  Future<void> close() async {
    ++_generation;
    await _closeSession();
    _enter(VaultStage.closed);
  }

  /// Deletes the store and its platform key, then opens a new, empty one.
  Future<void> reset() async {
    final generation = ++_generation;
    await _closeSession();
    _enter(VaultStage.opening);
    try {
      await _backend.reset();
    } on KeybayException catch (error) {
      if (generation == _generation) {
        _enter(VaultStage.failed, describe(error.code));
      }
      return;
    }
    if (generation == _generation) await open();
  }

  @override
  void dispose() {
    ++_generation;
    unawaited(_closeSession());
    super.dispose();
  }

  Future<void> _adopt(KeybaySession session, int generation) async {
    _session = session;
    createdNewStore = session.wasInitialized;
    try {
      await _refresh(session);
    } on KeybayException catch (error) {
      if (generation == _generation) {
        await _closeSession();
        _enter(VaultStage.failed, describe(error.code));
      }
      return;
    }
    if (generation == _generation) _enter(VaultStage.open);
  }

  Future<void> _refresh(KeybaySession session) async {
    keys = await session.listKeys();
    passphraseProtected = (await session.auth.list())
        .whereType<PassphraseMethod>()
        .isNotEmpty;
    notifyListeners();
  }

  Future<T> _withSession<T>(
    Future<T> Function(KeybaySession session) operation,
  ) async {
    final session = _session;
    if (session == null || stage != VaultStage.open) {
      throw StateError('The vault is closed.');
    }
    try {
      return await operation(session);
    } on KeybayException catch (error) {
      // Another process can change the store's protection; authenticate
      // again rather than keep using this session.
      if (error.code == KeybayErrorCode.staleSession ||
          error.code == KeybayErrorCode.storeAuthenticationFailed) {
        unawaited(open());
      }
      rethrow;
    }
  }

  Future<void> _closeSession() async {
    final session = _session;
    _session = null;
    keys = const [];
    if (session != null && !session.isClosed) await session.close();
  }

  void _enter(VaultStage next, [String? explanation]) {
    stage = next;
    message = explanation;
    notifyListeners();
  }

  static Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));
}

/// A short, user-facing description of a Keybay failure.
String describe(KeybayErrorCode code) => switch (code) {
  KeybayErrorCode.unlockFailed => 'Wrong passphrase.',
  KeybayErrorCode.invalidAuthInput => 'That passphrase is not allowed.',
  KeybayErrorCode.platformProtectorLocked =>
    'The device is locked. Unlock it and try again.',
  KeybayErrorCode.platformProtectorUnavailable =>
    'Secure storage is unavailable on this device.',
  KeybayErrorCode.applicationIdentityUnavailable =>
    'This build has no signed identity Keybay can use.',
  KeybayErrorCode.platformKeyInvalidated =>
    'The device key protecting this store is gone. Reset the store to start '
        'again.',
  KeybayErrorCode.invalidRecordKey => 'That name is not allowed.',
  KeybayErrorCode.limitExceeded => 'That is too large to store.',
  KeybayErrorCode.storeBusy => 'The store is busy. Try again.',
  KeybayErrorCode.staleSession ||
  KeybayErrorCode.storeAuthenticationFailed ||
  KeybayErrorCode.sessionClosed => 'The store changed. Reopening it.',
  _ => 'Keybay error: ${code.name}.',
};
