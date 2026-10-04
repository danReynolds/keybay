// Unattended test assembly: real SDK engine and TUI, exclusively fake storage,
// platform root and passkey provider. Never loads a physical hardware adapter.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngineTestProbe;
import 'package:keybay_cli/src/entrypoint.dart';
import '../../keybay/test/support/v2_passkey_backend.dart';
import '../../keybay/test/support/v2_test_keybay.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) throw ArgumentError('SCENARIO RECEIPT [--idle]');
  final scenario = arguments[0];
  if (!RegExp(
    r'^(enroll|unlock)-(pin|reject|blocked|wait)$',
  ).hasMatch(scenario)) {
    throw ArgumentError('Unknown hardware PTY scenario');
  }
  final receipt = File(arguments[1]);
  final events = <Map<String, Object?>>[];
  void record(String event, [Map<String, Object?> fields = const {}]) {
    events.add({'event': event, ...fields});
    final stage = File('${receipt.path}.tmp');
    stage.writeAsStringSync(jsonEncode(events), flush: true);
    stage.renameSync(receipt.path);
  }

  final provider = TestPasskeyProvider();
  final ownedInputs = <Uint8List>[];
  final sessions = <KeybaySession>[];
  final store = V2TestKeybay(
    applicationId: 'dev.keybay.hardware-pty',
    keypassClient: provider.client,
    probe: V2StoreEngineTestProbe(onOperationInput: ownedInputs.add),
  );
  const credential = PasskeyCredential.hardware(rpId: 'hardware-pty.test');
  final seed = await store.open();
  await seed.set('acme/key', 'disposable-value');
  if (scenario.startsWith('unlock-')) {
    await seed.auth.add(credential, label: 'Disposable hardware key');
  }
  await seed.close();
  ownedInputs.clear();
  final generation = store.files.liveGeneration;
  final initialOperations = provider.operationCount;
  var attempts = 0;
  provider.beforeEvaluation = (cancellation) async {
    // Enrollment evaluates more than once; count user operations, not stages.
    final attempt = provider.operationCount - initialOperations;
    if (attempt != attempts) {
      attempts = attempt;
      record('attempt', {'number': attempt});
    }
    if (scenario.endsWith('-wait') && attempt == 1) {
      final stopped = Completer<void>();
      final subscription = cancellation.onCancel.listen(
        (_) => stopped.complete(),
      );
      if (cancellation.isCancelled && !stopped.isCompleted) stopped.complete();
      try {
        // Fail boundedly if the TUI forgets to forward cancellation.
        await stopped.future.timeout(const Duration(seconds: 5));
        record('cancelled');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        record('drained');
      } finally {
        await subscription.cancel();
      }
    } else if (!scenario.endsWith('-wait')) {
      provider.nextFailure = switch (attempt) {
        1 => PasskeyErrorCode.pinRequired,
        2 when scenario.endsWith('-reject') => PasskeyErrorCode.pinInvalid,
        2 when scenario.endsWith('-blocked') => PasskeyErrorCode.pinBlocked,
        _ => null,
      };
    }
  };

  record('ready', {'pid': pid});
  try {
    final shortIdle = arguments.contains('--idle');
    exitCode = await runKeybay(
      ['open'],
      resetStore: store.reset,
      idleTimeout: shortIdle
          ? const Duration(seconds: 2)
          : const Duration(minutes: 5),
      idleWarning: const Duration(milliseconds: 200),
      openSession: ({credential, methodId, cancellation}) async {
        final session = await store.open(
          credential: credential,
          methodId: methodId,
          cancellation: cancellation,
        );
        sessions.add(session);
        record('opened', {'via': credential == null ? 'platform' : 'hardware'});
        return session;
      },
    );
    provider.expectReleased();
    record('finished', {
      'exitCode': exitCode,
      'attempts': attempts,
      'operations': provider.operationCount - initialOperations,
      'generationChanged': generation != store.files.liveGeneration,
      'sessionsClosed': sessions.every((session) => session.isClosed),
      'inputsCleared': ownedInputs.every(
        (bytes) => bytes.every((byte) => byte == 0),
      ),
      'capturedInputs': ownedInputs.length,
      'providerReleased': true,
    });
  } finally {
    await store.dispose();
    provider.clear();
    stderr.writeln('test:closed');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
