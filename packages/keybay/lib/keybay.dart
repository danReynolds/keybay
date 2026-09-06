/// One encrypted, platform-protected store for the current host application.
///
/// The public surface is deliberately limited to opening the resolved
/// application's store, operating through an authenticated session, and
/// resetting that same store. Platform selection, paths, providers, and
/// application identity remain internal and cannot be supplied at runtime.
library;

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
        PassphraseCredential,
        PassphraseMethod;
