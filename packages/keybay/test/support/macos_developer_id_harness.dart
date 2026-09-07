// Native qualification only: a fresh build-embedded namespace in the genuine
// account's login Keychain. No provider value or record plaintext is emitted.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/macos_account_home.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:keybay/src/v2/macos_unentitled_host_platform.dart';

Future<void> main(List<String> args) async {
  const nonce = String.fromEnvironment('KEYBAY_SECURITY_NONCE');
  const subject = String.fromEnvironment('KEYBAY_SECURITY_SUBJECT');
  const build = String.fromEnvironment('KEYBAY_SECURITY_BUILD');
  const app = String.fromEnvironment('keybay.application_id');
  const controlPath = String.fromEnvironment('KEYBAY_SECURITY_CONTROL');
  final phase = args.single;
  var passed = false;
  var stage = 'validate';
  var failureType = 'none';
  KeybaySession? session;
  try {
    _require(Platform.isMacOS && RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce));
    _require(RegExp(r'^git-commit:[0-9a-f]{40}$').hasMatch(subject));
    _require(app == 'dev.keybay.qualification.developerid.$nonce');
    _require(['seed', 'reopen', 'cleanup'].contains(phase));
    _require(phase == 'cleanup' || build == (phase == 'seed' ? '101' : '102'));
    stage = 'resolve_host';
    final host = await MacOSUnentitledHostPlatform().resolve();
    final roots = AppleMacOSLoginKeychainRootStore(
      accountHome: resolveMacOSAccountHome(),
    );
    final directory = Directory.fromUri(host.binding.canonicalFileRoot);
    final control = File(controlPath);
    if (phase == 'seed') {
      stage = 'seed_preflight';
      _require(!await roots.exists(host.binding.providerAddress));
      _require(!File('${directory.path}/keybay.v2.store').existsSync());
      _require(!control.existsSync());
      control.writeAsStringSync(nonce, flush: true);
      stage = 'seed_open';
      session = await Keybay.open();
      _require(session.wasInitialized);
      await session.set('continuity/nonce', nonce);
      await session.set('continuity/process', '$pid');
      stage = 'seed_auth';
      final phrase = _phrase();
      try {
        await session.auth.add(PassphraseCredential(phrase: phrase));
      } finally {
        phrase.fillRange(0, phrase.length, 0);
      }
    } else if (phase == 'reopen') {
      stage = 'reopen';
      _require(control.readAsStringSync() == nonce);
      await _reject(null, KeybayErrorCode.authRequired);
      final wrong = Uint8List.fromList(utf8.encode('wrong public phrase'));
      try {
        await _reject(
          PassphraseCredential(phrase: wrong),
          KeybayErrorCode.unlockFailed,
        );
      } finally {
        wrong.fillRange(0, wrong.length, 0);
      }
      final phrase = _phrase();
      try {
        session = await Keybay.open(
          credential: PassphraseCredential(phrase: phrase),
        );
      } finally {
        phrase.fillRange(0, phrase.length, 0);
      }
      _require(!session.wasInitialized);
      _require(await session.get('continuity/nonce') == nonce);
      final previous = int.parse((await session.get('continuity/process'))!);
      _require(previous > 0 && previous != pid);
      _require((await session.listKeys()).length == 2);
    }
    await session?.close();
    session = null;
    if (phase != 'seed') {
      stage = 'reset';
      _require(control.readAsStringSync() == nonce);
      await Keybay.reset();
      _require(!await roots.exists(host.binding.providerAddress));
      for (final name in ['keybay.v2.store', 'keybay.v2.stage']) {
        _require(!File('${directory.path}/$name').existsSync());
      }
      control.deleteSync();
    }
    passed = true;
  } on Object catch (error) {
    failureType = error is KeybayException
        ? error.code.name
        : '${error.runtimeType}';
    // Typed/public success or failure only; native error text stays private.
  } finally {
    try {
      await session?.close();
    } on Object {
      passed = false;
    }
  }
  stdout.writeln(
    jsonEncode({
      'kind': 'keybay-macos-developer-id',
      'nonce': nonce,
      'subject': subject,
      'build': build,
      'phase': phase,
      'pid': pid,
      'status': passed ? 'pass' : 'fail',
      if (!passed) 'failure_stage': stage,
      if (!passed) 'failure_type': failureType,
    }),
  );
  exitCode = passed ? 0 : 1;
}

Uint8List _phrase() => Uint8List.fromList(
  utf8.encode('keybay public developer-id fixture phrase'),
);

Future<void> _reject(KeybayCredential? credential, KeybayErrorCode code) async {
  try {
    final unexpected = await Keybay.open(credential: credential);
    await unexpected.close();
  } on KeybayException catch (error) {
    _require(error.code == code);
    return;
  }
  throw StateError('Unexpected authentication success');
}

void _require(bool value) {
  if (!value) throw StateError('Qualification assertion failed');
}
