import 'package:keybay/keybay.dart';

final class CliFailure implements Exception {
  CliFailure({required this.exitCode, required List<String> lines})
    : lines = List<String>.unmodifiable(lines);

  final int exitCode;
  final List<String> lines;

  void writeTo(StringSink sink) {
    for (final line in lines) {
      sink.writeln(line);
    }
  }
}

/// Maps the redacted V2 error code without incorporating provider detail.
CliFailure failureForKeybay(KeybayException error) {
  final lines = switch (error.code) {
    KeybayErrorCode.storeNotFound => <String>[
      'error: no encrypted Keybay store is available to unlock.',
      'Authentication did not create a replacement store or change its protection.',
    ],
    KeybayErrorCode.applicationIdentityUnavailable => <String>[
      'error: Keybay could not establish this CLI build\'s application identity.',
      'Install an official build or compile it with the Keybay build command.',
    ],
    KeybayErrorCode.platformProtectorUnavailable => <String>[
      'error: no qualified Keybay platform protector is available.',
      'Use a supported platform profile; Keybay will not fall back to weaker storage.',
    ],
    KeybayErrorCode.platformProtectorLocked ||
    KeybayErrorCode.platformInteractionRequired => <String>[
      'error: platform protection is locked or requires interaction.',
      'Unlock the platform key store and retry from an attended session.',
    ],
    KeybayErrorCode.platformKeyInvalidated => <String>[
      'error: the platform-protected store key is no longer usable.',
      'Restore the matching platform state or deliberately reset Keybay; existing values cannot be recovered without it.',
    ],
    KeybayErrorCode.authRequired
        when error.authMethods.whereType<PassphraseMethod>().isEmpty &&
            error.authMethods.whereType<PasskeyMethod>().isNotEmpty =>
      <String>[
        'error: no supported unlock method is available in this CLI.',
        'System passkeys require a supported app host. Use an enrolled hardware key or passphrase.',
      ],
    KeybayErrorCode.authRequired || KeybayErrorCode.unlockFailed => <String>[
      'error: Keybay authentication failed.',
      'Use a configured credential to reopen the store.',
    ],
    KeybayErrorCode.authMethodSelectionRequired => <String>[
      'error: more than one passkey method matches this request.',
      'Select a configured authentication method and retry.',
    ],
    KeybayErrorCode.passkeyOperationFailed => <String>[
      'error: ${hardwareFailureMessage(error.passkeyCode)}',
    ],
    KeybayErrorCode.protectionMismatch => <String>[
      'error: the supplied credential does not match the store protection.',
      'Reopen Keybay to authenticate its current protection; no automatic retry was made.',
    ],
    KeybayErrorCode.storeBusy => <String>[
      'error: the Keybay store is busy.',
      'Retry after the other Keybay operation completes.',
    ],
    KeybayErrorCode.resetIncomplete => <String>[
      'error: a previous Keybay reset did not complete.',
      'Preserve the store; completing reset requires another deliberate confirmation.',
    ],
    KeybayErrorCode.storeAuthenticationFailed ||
    KeybayErrorCode.unsupportedStoreVersion ||
    KeybayErrorCode.storeStateConflict => <String>[
      'error: Keybay could not authenticate a single supported store state.',
      'Preserve the existing state and follow the documented recovery procedure.',
    ],
    KeybayErrorCode.staleSession || KeybayErrorCode.sessionClosed => <String>[
      'error: the Keybay session is no longer usable.',
      'Retry the command to open a fresh session.',
    ],
    KeybayErrorCode.invalidRecordKey ||
    KeybayErrorCode.invalidRecordEncoding ||
    KeybayErrorCode.limitExceeded ||
    KeybayErrorCode.invalidAuthInput => <String>[
      'error: the supplied Keybay input is invalid or exceeds a limit.',
      'Check the key, value, or passphrase and retry.',
    ],
    KeybayErrorCode.authMethodAlreadyConfigured ||
    KeybayErrorCode.authMethodNotConfigured => <String>[
      'error: the requested authentication configuration is not valid for this store.',
      'Reopen Keybay and inspect its configured authentication methods.',
    ],
    KeybayErrorCode.platformOperationFailed ||
    KeybayErrorCode.storageOperationFailed ||
    KeybayErrorCode.entropyUnavailable => <String>[
      'error: a required secure Keybay operation failed.',
      'A submitted operation may have completed. Preserve the store and reopen to inspect state before retrying.',
    ],
  };

  final inputFailure = switch (error.code) {
    KeybayErrorCode.invalidRecordKey ||
    KeybayErrorCode.invalidRecordEncoding ||
    KeybayErrorCode.limitExceeded ||
    KeybayErrorCode.invalidAuthInput => true,
    _ => false,
  };
  return CliFailure(exitCode: inputFailure ? 2 : 1, lines: lines);
}

String hardwareFailureMessage(PasskeyErrorCode? code) => switch (code) {
  PasskeyErrorCode.pinRequired =>
    'Enter the existing PIN for your hardware key.',
  PasskeyErrorCode.pinInvalid =>
    'That PIN was rejected. Check it before trying again.',
  PasskeyErrorCode.pinBlocked =>
    'The hardware PIN is blocked. Stop and use another unlock method.',
  PasskeyErrorCode.pinTemporarilyBlocked =>
    'The key temporarily blocked PIN attempts. Reconnect it before a deliberate retry.',
  PasskeyErrorCode.pinChangeRequired =>
    'The key requires a PIN change in its management app.',
  PasskeyErrorCode.deviceUnavailable =>
    'No hardware key is available. Connect your key and try again.',
  PasskeyErrorCode.deviceSelectionRequired =>
    'Connect only the hardware key you want to use.',
  PasskeyErrorCode.credentialUnavailable =>
    'This key does not have the selected passkey. Use the matching key.',
  PasskeyErrorCode.credentialStorageFull =>
    'The hardware key has no room for another passkey.',
  PasskeyErrorCode.prfUnavailable || PasskeyErrorCode.verificationUnavailable =>
    'This key cannot provide the encryption and verification capabilities Keybay requires.',
  PasskeyErrorCode.cancelled => 'The hardware operation was cancelled.',
  PasskeyErrorCode.timeout =>
    'The key did not finish in time. Retry when you are ready to touch it.',
  PasskeyErrorCode.backendUnavailable || PasskeyErrorCode.hostUnavailable =>
    'The hardware adapter is unavailable. Use a Keybay build with hardware support.',
  PasskeyErrorCode.busy =>
    'A hardware operation is still finishing. Wait before retrying.',
  _ => 'Hardware verification did not complete. Check the key before retrying.',
};
