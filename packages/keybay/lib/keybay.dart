/// One encrypted, platform-protected store for the current host application.
///
/// ```dart
/// final session = await Keybay.open();
/// try {
///   await session.set('api-token', 's3cr3t');
///   final token = await session.get('api-token');
/// } finally {
///   await session.close();
/// }
/// ```
///
/// The public surface is deliberately limited to hardening the host process,
/// opening the resolved application's store, operating through an
/// authenticated session, and resetting that same store. Platform selection,
/// paths, providers, and application identity remain internal and cannot be
/// supplied at runtime.
///
/// Call [Keybay.hardenProcess] first in `main` to keep core files, and on
/// Linux same-user debuggers, away from the secrets this process holds.
///
/// To require a passphrase or passkey, enroll one with
/// [KeybayAuthManager.add] and open later sessions with
/// `Keybay.open(credential: ...)`. Handle failures by [KeybayErrorCode].
library;

export 'src/process_hardening.dart'
    show KeybayHardeningMeasure, KeybayHardeningStatus, KeybayProcessHardening;
export 'src/v2/keybay_v2.dart'
    show
        AuthMethod,
        Keybay,
        KeybayAuthManager,
        KeybayCredential,
        KeybayErrorCode,
        KeybayException,
        KeybayLimits,
        KeybaySession,
        PasskeyCredential,
        PasskeyMethod,
        PassphraseCredential,
        PassphraseMethod;

export 'package:keypass/keypass.dart'
    show PasskeyCancellation, PasskeyErrorCode, PasskeyRoute;
