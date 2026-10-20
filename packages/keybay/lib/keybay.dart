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
/// The public surface is deliberately limited to opening the resolved
/// application's store, operating through an authenticated session, resetting
/// that same store, and reporting the process hardening applied on the way.
/// Platform selection, paths, providers, and application identity remain
/// internal and cannot be supplied at runtime.
///
/// Keybay hardens the host process at the first open, keeping core files and,
/// on Linux, same-user debuggers away from the secrets it holds; read
/// [Keybay.processHardening] for what it applied.
///
/// To require a passphrase or passkey, enroll one with
/// [KeybayAuthManager.add] and open later sessions with
/// `Keybay.open(credential: ...)`. Handle failures by [KeybayErrorCode].
library;

export 'src/process_hardening.dart'
    show
        KeybayHardeningCause,
        KeybayHardeningMeasure,
        KeybayHardeningStatus,
        KeybayProcessHardening;
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
