part of 'keybay_v2.dart';

/// Request/configuration metadata for passkey authentication.
/// Construction presents no UI and contains no secret. Keybay obtains and
/// disposes the Keypass result internally. RP scope does not change Keybay's
/// host identity, file location or mandatory platform protection.
final class PasskeyCredential extends KeybayCredential {
  const PasskeyCredential.system({
    required this.rpId,
    this.displayName,
    this.label = 'Keybay vault',
    this.methodId,
    this.cancellation,
  }) : route = PasskeyRoute.system,
       requestPin = null,
       selectConnection = null,
       onEvent = null;

  const PasskeyCredential.hardware({
    required this.rpId,
    this.displayName,
    this.label = 'Keybay vault',
    this.methodId,
    this.cancellation,
    this.requestPin,
    this.selectConnection,
    this.onEvent,
  }) : route = PasskeyRoute.hardware;

  final String rpId;
  final String? displayName;

  /// Used when enrolling/replacing a method; ignored when unlocking one.
  final String label;

  /// Select exactly this method. Updates require an ID. Unlock may omit it
  /// only when one stored method matches this RP and route. Adds omit it.
  final String? methodId;
  final PasskeyRoute route;
  final PasskeyCancellation? cancellation;

  /// Obtain any vault data before starting authentication. Calling Keybay
  /// operations from a hardware callback fails with `storeBusy` to avoid
  /// waiting on the operation that is itself waiting for this callback.
  final HardwarePinPrompt? requestPin;
  final HardwareConnectionPicker? selectConnection;
  final void Function(HardwareEvent)? onEvent;

  @override
  String toString() => 'PasskeyCredential(${route.name})';
}

/// A configured passkey method. Credential records and key material stay inside
/// Keybay. Removing a method does not delete the provider's passkey.
final class PasskeyMethod extends AuthMethod {
  const PasskeyMethod._(
    super.id, {
    required this.rpId,
    required this.route,
    required this.label,
  }) : super._();

  final String rpId;
  final PasskeyRoute route;
  final String label;

  @override
  String toString() => 'PasskeyMethod(id: $id, route: ${route.name})';
}

_CredentialSnapshot _snapshotPasskey(PasskeyCredential credential) {
  try {
    // Constructor validation only; this opens no native backend or dialog.
    _defaultKeypassClient(credential);
    if (credential.methodId case final id?) decodeMethodId(id);
    final labelBytes = utf8.encode(credential.label);
    if (credential.label.trim().isEmpty ||
        labelBytes.length > v2MaxMethodLabelBytes ||
        utf8.decode(labelBytes) != credential.label) {
      throw const FormatException('Invalid label');
    }
    return _CredentialSnapshot.passkey(credential);
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
        requestPin: credential.requestPin,
        selectConnection: credential.selectConnection,
        onEvent: credential.onEvent,
      ),
    };
