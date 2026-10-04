part of 'keybay_v2.dart';

/// Authentication input for a passkey operation.
/// Construction presents no UI. A hardware PIN borrows caller-owned bytes,
/// just like a passphrase; operations snapshot and clear their own copy.
/// Keybay obtains and disposes the Keypass result internally. RP scope does not
/// change Keybay's host identity, file location or mandatory platform protection.
final class PasskeyCredential extends KeybayCredential {
  const PasskeyCredential.system({required this.rpId, this.displayName})
    : route = PasskeyRoute.system,
      _pin = null;

  /// Use a physical FIDO2 key. [pin] borrows caller-owned UTF-8 bytes.
  /// Omit it when the key/provider handles verification. Missing required PINs
  /// report `pinRequired`; rejected PINs are never retried automatically.
  /// A sole connection is selected automatically; ambiguous discovery reports
  /// `deviceSelectionRequired` rather than silently choosing a key.
  const PasskeyCredential.hardware({
    required this.rpId,
    this.displayName,
    Uint8List? pin,
  }) : route = PasskeyRoute.hardware,
       _pin = pin;

  final String rpId;
  final String? displayName;

  final PasskeyRoute route;
  final Uint8List? _pin;

  @override
  String toString() => 'PasskeyCredential(${route.name})';
}

/// A configured passkey method. Credential records and key material stay inside
/// Keybay. Removing a method does not delete the provider's passkey.
final class PasskeyMethod extends AuthMethod {
  const PasskeyMethod._(
    String id, {
    required String storeId,
    required this.rpId,
    required this.route,
    required String label,
  }) : super._(id, storeId, label: label);

  final String rpId;
  final PasskeyRoute route;

  @override
  String toString() => 'PasskeyMethod(id: $id, route: ${route.name})';
}

PasskeyCredential _snapshotPasskey(PasskeyCredential credential) {
  try {
    // Constructor validation only; this opens no native backend or dialog.
    _defaultKeypassClient(credential);
    final pin = credential._pin;
    if (pin != null && (pin.length < 4 || pin.length > 63 || pin.contains(0))) {
      throw const FormatException('Invalid PIN');
    }
    return switch (credential.route) {
      PasskeyRoute.system => credential,
      PasskeyRoute.hardware => PasskeyCredential.hardware(
        rpId: credential.rpId,
        displayName: credential.displayName,
        pin: pin == null ? null : Uint8List.fromList(pin),
      ),
    };
  } on Object {
    throw _error(KeybayErrorCode.invalidAuthInput, 'Invalid passkey request.');
  }
}

Keypass _defaultKeypassClient(PasskeyCredential credential) =>
    switch (credential.route) {
      PasskeyRoute.system => Keypass.system(
        rpId: credential.rpId,
        displayName: credential.displayName,
      ),
      PasskeyRoute.hardware => Keypass.hardware(
        rpId: credential.rpId,
        displayName: credential.displayName,
        // Keypass owns each reply. Give it a fresh copy for each ceremony
        // stage; never transfer the caller's bytes or our operation snapshot.
        requestPin: credential._pin == null
            ? null
            : (_, cancellation) async => cancellation.isCancelled
                  ? null
                  : Uint8List.fromList(credential._pin),
      ),
    };
