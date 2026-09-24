import 'package:keybay/keybay.dart';

/// Opens this app's one Keybay store. The app reaches Keybay only through this
/// seam, so widget tests can run against the SDK's in-memory engine.
abstract interface class VaultBackend {
  Future<KeybaySession> open({KeybayCredential? credential});

  Future<void> reset();
}

/// The real store, protected by this device's platform keystore under the
/// app's signed identity.
final class KeybayBackend implements VaultBackend {
  const KeybayBackend();

  @override
  Future<KeybaySession> open({KeybayCredential? credential}) =>
      Keybay.open(credential: credential);

  @override
  Future<void> reset() => Keybay.reset();
}
