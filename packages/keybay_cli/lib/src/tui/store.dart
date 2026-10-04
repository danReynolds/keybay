import 'dart:typed_data';

/// The storage operations used by the TUI. The native adapter delegates to
/// Keybay; the website supplies disposable, in-memory demo data.
///
/// Consume or copy [phrase] and [pin] before returning the future: the model immediately
/// clears its borrowed input. The returned session belongs to the model.
typedef TuiSessionOpener =
    Future<TuiSession> Function({
      Uint8List? phrase,
      TuiAuthMethod? method,
      Uint8List? pin,
      TuiCancellation? cancellation,
    });

enum TuiAuthKind { passphrase, hardware, system }

/// Nonsecret presentation metadata. The native implementation retains the SDK
/// descriptor so removal passes the original vault-bound object back to it.
abstract interface class TuiAuthMethod {
  String get id;
  String get label;
  TuiAuthKind get kind;
  String? get rpId;
}

/// One attempt's cancellation, portable to the synthetic website host.
/// Binding is synchronous so cancellation cannot race adapter setup.
final class TuiCancellation {
  bool _cancelled = false;
  void Function()? _callback;
  bool get isCancelled => _cancelled;
  void bind(void Function() callback) {
    _callback = callback;
    if (_cancelled) callback();
  }

  void unbind() => _callback = null;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _callback?.call();
  }
}

const tuiRecordValueBytes = 1024 * 1024;

/// An invocation-owned session, independent of native providers and widgets.
/// Returned bytes belong to the caller. Mutable inputs must be consumed or
/// copied before returning a future, because the caller immediately clears them.
abstract interface class TuiSession {
  /// Whether this open created a new store, for the first-use screen.
  bool get wasInitialized;
  Future<List<String>> listKeys();
  Future<List<TuiAuthMethod>> listMethods();
  Future<Uint8List?> getBytes(String key);
  Future<void> setBytes(String key, Uint8List value);
  Future<bool> delete(String key);
  Future<void> clearAll();
  Future<void> addPassphrase(Uint8List phrase);
  Future<void> addHardwareKey({
    required String label,
    Uint8List? pin,
    required TuiCancellation cancellation,
  });
  Future<void> removeMethod(TuiAuthMethod method);
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
    this.methods = const [],
    this.hardware = false,
    this.needsPin = false,
    this.retryHardware = true,
  });

  final String message;
  final TuiUnlockFailure? unlock;
  final bool canReset;
  final bool resetIncomplete;
  final bool invalidatesSession;
  final List<TuiAuthMethod> methods;

  /// A provider failure before an auth change commits. The session may stay
  /// open, unlike a storage/commit failure with an ambiguous outcome.
  final bool hardware;
  final bool needsPin;
  final bool retryHardware;
}
