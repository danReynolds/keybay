import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:keybay/src/v2/macos_unentitled_host_platform.dart';

Future<void> main(List<String> args) async {
  Future<void> phase(String value) async {
    stderr.writeln('locked-keychain-phase: $value');
    await stderr.flush();
  }

  final accountHome = Platform.environment['KEYBAY_TEST_KEYCHAIN_HOME']!;
  final helper = Platform.environment['KEYBAY_TEST_KEYCHAIN_HELPER']!;
  final keychain = '$accountHome/Library/Keychains/login.keychain-db';
  final platform = MacOSUnentitledHostPlatform.test(
    identity: ApplicationIdentity(
      stableValue: 'dev.keybay.locked-native.$pid',
      source: ApplicationIdentitySource.test,
      assurance: ApplicationIdentityAssurance.namespaceOnly,
    ),
    canonicalFileRoot: Uri.directory(args.single),
    rootStore: AppleMacOSLoginKeychainRootStore(accountHome: accountHome),
  );
  await phase('open');
  final stale = await V2StoreEngine(platform).open();
  try {
    await stale.set('record', 'fixed test value');
    final current = await V2StoreEngine(platform).open();
    try {
      // Prepare both session states before locking. Unlocking the provider
      // is not needed to verify prompt-free current and stale record paths.
      await phase('rotate');
      final phrase = Uint8List.fromList(utf8.encode('fixed test passphrase'));
      try {
        await current.auth.add(PassphraseCredential(phrase: phrase));
      } finally {
        phrase.fillRange(0, phrase.length, 0);
      }
      await phase('fixture-lock');
      final lock = await Process.run(helper, ['lock', keychain]);
      if (lock.exitCode != 0) {
        throw StateError('Fixture lock failed: ${lock.stdout}');
      }
      await phase('locked-record-operations');
      if (await current.get('record') != 'fixed test value') {
        throw StateError('Existing session read failed');
      }
      await current.set('record', 'updated test value');
      await current.listKeys();
      await current.auth.list();
      await phase('locked-stale-read');
      try {
        await stale.get('record');
        throw StateError('Stale session unexpectedly read rotated data');
      } on KeybayException catch (failure) {
        if (failure.code != KeybayErrorCode.storeAuthenticationFailed) rethrow;
      }
    } finally {
      await current.close();
    }
  } finally {
    await stale.close();
  }
  // The host owns file cleanup and deletion of the disposable Keychain.
  stdout.writeln('locked-records-ok');
}
