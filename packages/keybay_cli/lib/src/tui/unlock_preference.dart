/// A local UI hint, never authentication material or an authorization decision.
/// A remembered ID is usable only if the current store offers that method.
abstract interface class UnlockPreference {
  Future<String?> read();
  Future<void> write(String methodId);
}
