/// Cross-platform device-access policy and store configuration for Keybay V2.
library;

/// When the operating system's key store may unseal the vault's platform root.
///
/// Enforced on mobile and Apple Data Protection key stores (iOS, entitled
/// macOS, and Android 12+). Desktop login keyrings (unentitled macOS and Linux)
/// govern lock state at the user-session level and treat this setting as a
/// documented no-op.
enum KeybayDeviceAccess {
  /// Strict default: the platform root is usable only while the device is
  /// unlocked (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on Apple Data
  /// Protection Keychain; `setUnlockedDeviceRequired(true)` on Android 12+
  /// Keystore).
  ///
  /// Android note: `setUnlockedDeviceRequired(true)` relies on Android's
  /// lock-screen key protection (LSKF). Removing the device screen lock
  /// invalidates keys created with this flag (`platformKeyInvalidated`), and
  /// Android 12–14 devices unlocked via Class 1/2 (non-strong) biometrics may
  /// report `platformProtectorLocked` until unlocked with PIN/strong biometric.
  whenUnlocked,

  /// Opt-in for background tasks (such as iOS `BGAppRefreshTask` or Android
  /// `WorkManager`): the platform root remains usable after the device's first
  /// unlock since boot, even while the screen is locked
  /// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on Apple Data
  /// Protection Keychain; `setUnlockedDeviceRequired(false)` on Android 12+
  /// Keystore).
  afterFirstUnlock,
}

/// Configuration for initializing a Keybay vault.
///
/// Top-level fields capture policies that translate directly across supported
/// operating-system key stores. Platform-specific options, when introduced,
/// belong in nested per-platform option objects rather than flat
/// platform-prefixed fields.
final class KeybayOptions {
  /// Creates vault configuration. Defaults to the strictest protection
  /// ([KeybayDeviceAccess.whenUnlocked]).
  const KeybayOptions({this.deviceAccess = KeybayDeviceAccess.whenUnlocked});

  /// When the platform key store may unseal the vault root on a newly
  /// initialized vault.
  ///
  /// Passing [KeybayOptions] to `Keybay.open` applies only when initializing
  /// absent state; it never silently changes protection on an existing vault.
  /// Call `session.setDeviceAccess` on an open session to change an existing
  /// vault's policy.
  final KeybayDeviceAccess deviceAccess;

  @override
  bool operator ==(Object other) =>
      other is KeybayOptions && other.deviceAccess == deviceAccess;

  @override
  int get hashCode => deviceAccess.hashCode;

  @override
  String toString() => 'KeybayOptions(deviceAccess: ${deviceAccess.name})';
}
