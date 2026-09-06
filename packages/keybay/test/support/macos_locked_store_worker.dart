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

  await phase('start');
  final accountHome = Platform.environment['KEYBAY_TEST_KEYCHAIN_HOME']!;
  final helper = Platform.environment['KEYBAY_TEST_KEYCHAIN_HELPER']!;
  final keychain = '$accountHome/Library/Keychains/login.keychain-db';
  Future<void> fixture(String action) async {
    await phase('fixture-$action');
    final result = await Process.run(helper, [action, keychain]);
    if (result.exitCode != 0) {
      // The dedicated helper emits only its action and numeric OS status.
      throw StateError('Fixture $action failed: ${result.stdout}');
    }
  }

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
  final session = await V2StoreEngine(platform).open();
  try {
    await session.set('record', 'fixed test value');
    await fixture('lock');
    await phase('locked-record-operations');
    if (await session.get('record') != 'fixed test value') {
      throw StateError('Existing session read failed');
    }
    await session.set('record', 'updated test value');
    await session.listKeys();
    await session.auth.list();
    await fixture('unlock');

    await phase('open-peer');
    final peer = await V2StoreEngine(platform).open();
    try {
      final phrase = Uint8List.fromList(utf8.encode('fixed test passphrase'));
      try {
        await phase('rotate');
        await peer.auth.add(PassphraseCredential(phrase: phrase));
      } finally {
        phrase.fillRange(0, phrase.length, 0);
      }
    } finally {
      await peer.close();
    }
    await fixture('lock');
    await phase('locked-stale-read');
    try {
      await session.get('record');
      throw StateError('Stale session unexpectedly read rotated data');
    } on KeybayException catch (failure) {
      if (failure.code != KeybayErrorCode.storeAuthenticationFailed) rethrow;
    }
  } finally {
    await phase('cleanup');
    await fixture('unlock');
    await session.close();
    await V2StoreEngine(platform).reset();
  }
  stdout.writeln('locked-records-ok');
}
