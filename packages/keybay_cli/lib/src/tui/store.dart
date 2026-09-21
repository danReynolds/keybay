import 'dart:typed_data';

/// The storage operations used by the TUI. The native adapter delegates to
/// Keybay; the website supplies disposable, in-memory demo data.
///
/// Consume or copy [phrase] before returning the future: the model immediately
/// clears its borrowed input. The returned session belongs to the model.
typedef TuiSessionOpener = Future<TuiSession> Function({Uint8List? phrase});

const tuiRecordValueBytes = 1024 * 1024;

/// An invocation-owned session, independent of native providers and widgets.
/// Returned bytes belong to the caller. Mutable inputs must be consumed or
/// copied before returning a future, because the caller immediately clears them.
abstract interface class TuiSession {
  /// Whether this open created a new store, for the first-use screen.
  bool get wasInitialized;
  Future<List<String>> listKeys();
  Future<String?> passphraseId();
  Future<Uint8List?> getBytes(String key);
  Future<void> setBytes(String key, Uint8List value);
  Future<bool> delete(String key);
  Future<void> clearAll();
  Future<void> changePassphrase(Uint8List phrase, {required bool replacing});
  Future<void> removePassphrase(String id);
  Future<void> close();
}

enum TuiUnlockFailure { missing, incorrect }

/// Redacted presentation consequences of a storage failure. The native adapter
/// owns SDK error classification; the UI never handles provider diagnostics.
final class TuiStoreException implements Exception {
  const TuiStoreException(
    this.message, {
    this.unlock,
    this.canReset = false,
    this.resetIncomplete = false,
    this.invalidatesSession = false,
  });

  final String message;
  final TuiUnlockFailure? unlock;
  final bool canReset;
  final bool resetIncomplete;
  final bool invalidatesSession;
}
