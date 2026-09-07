// Dedicated device fixture: explicit seed/reopen launches share a compiled nonce.
// Process mode reuses build 101; upgrade mode replaces 101 with 102 and verifies
// passphrase protection. Neither reopen may initialize a store.
// Crash mode keeps seed/mutate alive for an exact native SIGKILL. Public atomic
// acknowledgments bound recovery to the last completed write or its successor.
// A reopen can never initialize successfully. The public control file separates
// app-container loss from loss of only Keybay's encrypted store.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:keybay/keybay.dart';
// Native identity oracle for this dedicated device fixture.
// ignore: implementation_imports
import 'package:keybay/src/ffi/apple_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const nonce = String.fromEnvironment('KEYBAY_SECURITY_NONCE');
  const subject = String.fromEnvironment('KEYBAY_SECURITY_SUBJECT');
  const mode = String.fromEnvironment(
    'KEYBAY_LIFECYCLE_MODE',
    defaultValue: 'process',
  );
  const build = String.fromEnvironment(
    'KEYBAY_LIFECYCLE_BUILD',
    defaultValue: '101',
  );
  String? phase;
  File? control;
  File? resultFile;
  File? acknowledgement;
  KeybaySession? session;
  var passed = false;
  var reason = 'operation_failed';
  String receipt(String status, String reason) => jsonEncode({
    'kind': 'keybay-mobile-lifecycle',
    'nonce': nonce,
    'subject': subject,
    'mode': mode,
    'build': build,
    'pid': pid,
    'phase': ['seed', 'mutate', 'reopen', 'cleanup'].contains(phase)
        ? phase
        : 'invalid',
    'status': status,
    'reason': reason,
  });
  try {
    phase = await const MethodChannel(
      'dev.keybay.securityharness/keybay_device_security',
    ).invokeMethod<String>('lifecyclePhase');
    _require(
      phase == 'seed' ||
          phase == 'reopen' ||
          (mode == 'crash' && ['mutate', 'cleanup'].contains(phase)),
      'invalid_phase',
    );
    _require(['process', 'upgrade', 'crash'].contains(mode), 'invalid_mode');
    _require(
      build == (mode == 'upgrade' && phase == 'reopen' ? '102' : '101'),
      'wrong_build',
    );
    _require(RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce), 'invalid_nonce');
    _require(
      RegExp(r'^git-commit:[0-9a-f]{40}$').hasMatch(subject),
      'invalid_source',
    );
    final String root;
    if (Platform.isIOS) {
      final api = AppleHostApi.ios();
      _require(
        api.bundleIdentifier() == 'dev.keybay.securityharness',
        'wrong_app',
      );
      root = api.applicationSupportDirectory();
    } else {
      _require(Platform.isAndroid, 'unsupported_platform');
      final facts = await const MethodChannel(
        'dev.keybay.securityharness/keybay_device_security',
      ).invokeMethod<Map<Object?, Object?>>('hostFacts');
      _require(
        facts?['packageName'] == 'dev.keybay.securityharness',
        'wrong_app',
      );
      root = facts!['noBackupFilesDir'] as String;
    }
    control = File('$root/keybay-lifecycle-control.json');
    resultFile = File('$root/keybay-lifecycle-result.json');
    acknowledgement = File('$root/keybay-lifecycle-ack.json');
    if (phase == 'cleanup') {
      if (control.existsSync()) {
        final previous =
            jsonDecode(control.readAsStringSync()) as Map<String, dynamic>;
        _require(previous['nonce'] == nonce, 'cleanup_nonce_mismatch');
      }
    } else if (phase == 'seed') {
      await Keybay.reset();
      session = await Keybay.open();
      _require(session.wasInitialized, 'seed_not_fresh');
      await session.set('continuity/nonce', nonce);
      await session.set('continuity/process', '$pid');
      if (mode != 'process') {
        final phrase = _phrase();
        try {
          await session.auth.add(PassphraseCredential(phrase: phrase));
        } finally {
          phrase.fillRange(0, phrase.length, 0);
        }
      }
      if (mode != 'crash') {
        await session.close();
        session = null;
      }
      control.writeAsStringSync(
        jsonEncode({'nonce': nonce, 'pid': pid, 'mode': mode, 'build': build}),
        flush: true,
      );
    } else {
      _require(control.existsSync(), 'control_missing');
      final previous =
          jsonDecode(control.readAsStringSync()) as Map<String, dynamic>;
      _require(previous['nonce'] == nonce, 'control_nonce_mismatch');
      _require(
        previous['mode'] == mode && previous['build'] == '101',
        'control_build_mismatch',
      );
      final previousPid = previous['pid'];
      _require(
        previousPid is int && previousPid > 0 && previousPid != pid,
        'process_not_changed',
      );
      if (mode != 'process') {
        await _expectOpenFailure(null, KeybayErrorCode.authRequired);
        final wrong = Uint8List.fromList(
          utf8.encode('wrong-public-fixture-phrase'),
        );
        try {
          await _expectOpenFailure(
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
      } else {
        session = await Keybay.open();
      }
      _require(!session.wasInitialized, 'fresh_store_on_reopen');
      _require(
        await session.get('continuity/nonce') == nonce,
        'store_nonce_mismatch',
      );
      _require(
        await session.get('continuity/process') == '$previousPid',
        'store_process_mismatch',
      );
      final keys = await session.listKeys();
      _require(
        keys.length == (mode == 'crash' && phase == 'reopen' ? 3 : 2) &&
            keys.contains('continuity/nonce') &&
            keys.contains('continuity/process'),
        'unexpected_records',
      );
      if (mode == 'crash' && phase == 'reopen') {
        final ack =
            jsonDecode(acknowledgement.readAsStringSync())
                as Map<String, dynamic>;
        final index = ack['index'];
        _require(
          ack.length == 7 &&
              ack['nonce'] == nonce &&
              ack['subject'] == subject &&
              ack['mode'] == mode &&
              ack['build'] == build &&
              ack['phase'] == 'mutate' &&
              ack['pid'] is int &&
              ack['pid'] > 0 &&
              ack['pid'] != pid &&
              ack['pid'] != previousPid &&
              index is int &&
              index >= 0,
          'invalid_acknowledgement',
        );
        final recovered = int.tryParse(
          await session.get('crash/sequence') ?? '',
        );
        _require(
          recovered == index || recovered == index + 1,
          'non_atomic_recovery',
        );
        await session.set('crash/recovered', nonce);
        _require(
          await session.get('crash/recovered') == nonce,
          'write_after_recovery_failed',
        );
      }
    }
    if (mode == 'crash' && ['seed', 'mutate'].contains(phase)) {
      final deadline = Stopwatch()..start();
      var index = 0;
      while (deadline.elapsed < const Duration(minutes: 2)) {
        if (phase == 'mutate') {
          await session!.set('crash/sequence', '$index');
          final stage = File('${acknowledgement.path}.stage');
          stage.writeAsStringSync(
            jsonEncode({
              'nonce': nonce,
              'subject': subject,
              'mode': mode,
              'build': build,
              'phase': phase,
              'pid': pid,
              'index': index,
            }),
            flush: true,
          );
          stage.renameSync(acknowledgement.path);
        }
        if (index == 0) {
          resultFile.writeAsStringSync(
            '${receipt('ready', 'awaiting_termination')}\n',
            flush: true,
          );
        }
        index++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      throw const _ProbeFailure('native_termination_not_observed');
    }
    passed = true;
    reason = 'completed';
  } on _ProbeFailure catch (failure) {
    reason = failure.code;
  } on KeybayException catch (failure) {
    reason = failure.code.name;
  } on Object {
    // Provider/native errors and assertion values stay out of the receipt.
  } finally {
    try {
      await session?.close();
      if (control != null && (phase != 'seed' || !passed)) {
        await Keybay.reset();
        if (control.existsSync()) control.deleteSync();
        if (acknowledgement != null) {
          for (final file in [
            acknowledgement,
            File('${acknowledgement.path}.stage'),
          ]) {
            if (file.existsSync()) file.deleteSync();
          }
        }
      }
    } on Object {
      passed = false;
      reason = 'cleanup_failed';
    }
  }
  final finalReceipt = receipt(passed ? 'pass' : 'fail', reason);
  // Device launchers may discard app stdout and Flutter's platform log. Keep
  // the public receipt in the dedicated app container for exact retrieval.
  // The host must verify phase, nonce, source, and the native process exit.
  try {
    resultFile?.writeAsStringSync('$finalReceipt\n', flush: true);
  } on Object {
    exit(1);
  }
  // ignore: avoid_print
  print(finalReceipt);
  exit(passed ? 0 : 1);
}

// Public test material; never a user's credential.
Uint8List _phrase() => Uint8List.fromList(
  utf8.encode('keybay-public-lifecycle-fixture-passphrase'),
);

Future<void> _expectOpenFailure(
  KeybayCredential? credential,
  KeybayErrorCode code,
) async {
  try {
    final unexpected = await Keybay.open(credential: credential);
    await unexpected.close();
  } on KeybayException catch (failure) {
    _require(failure.code == code, 'wrong_auth_failure');
    return;
  }
  throw const _ProbeFailure('auth_bypass');
}

void _require(bool value, String code) {
  if (!value) throw _ProbeFailure(code);
}

final class _ProbeFailure implements Exception {
  const _ProbeFailure(this.code);
  final String code;
}
