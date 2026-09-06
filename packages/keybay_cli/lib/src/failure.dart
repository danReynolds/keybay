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
    KeybayErrorCode.authRequired ||
    KeybayErrorCode.protectionMismatch ||
    KeybayErrorCode.unlockFailed => <String>[
      'error: Keybay authentication failed.',
      'Check the passphrase and retry.',
    ],
    KeybayErrorCode.storeBusy => <String>[
      'error: the Keybay store is busy.',
      'Retry after the other Keybay operation completes.',
    ],
    KeybayErrorCode.resetIncomplete => <String>[
      'error: a previous Keybay reset did not complete.',
      'Retry the reset before accessing this store.',
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
      'Retry once; if it persists, preserve the store and report the failure.',
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
