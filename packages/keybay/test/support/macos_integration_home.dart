import 'dart:io';

import 'package:keybay/src/v2/macos_account_home.dart';

/// Lets native qualification pin the production binding to a disposable
/// `Library/Keychains/login.keychain-db` without changing runtime host resolution.
String macOSIntegrationAccountHome() =>
    Platform.environment['KEYBAY_TEST_KEYCHAIN_HOME'] ??
    resolveMacOSAccountHome();
