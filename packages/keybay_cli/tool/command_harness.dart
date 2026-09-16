// Test-only assembly: production command paths and SDK engine, disposable
// file/protector boundaries. This entrypoint is never in a release artifact.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/entrypoint.dart';
import 'package:keybay_cli/src/tui/model.dart'
    show tuiIdleTimeout, tuiIdleWarning;
import '../../keybay/test/support/v2_test_keybay.dart';

Future<void> main(List<String> arguments) async {
  final args = List<String>.of(arguments);
  final store = V2TestKeybay(applicationId: 'dev.keybay.cli-pty');
  final session = await store.open();
  await session.set('acme/key', 'disposable-value');
  if (!args.remove('--platform-only')) {
    final phrase = utf8.encode('disposable-passphrase');
    await session.auth.add(PassphraseCredential(phrase: phrase));
    phrase.fillRange(0, phrase.length, 0);
  }
  await session.close();
  final delayed = args.remove('--delay-open');
  final delayedUnlock = args.remove('--delay-unlock');
  final shortIdle = args.remove('--short-idle');
  var first = true;
  try {
    exitCode = await runKeybay(
      args,
      resetStore: store.reset,
      idleTimeout: shortIdle
          ? const Duration(milliseconds: 300)
          : tuiIdleTimeout,
      idleWarning: shortIdle
          ? const Duration(milliseconds: 150)
          : tuiIdleWarning,
      openSession: ({credential}) async {
        if (delayedUnlock && credential != null) {
          final gate = Completer<void>();
          store.gateNextOperation(gate.future);
          Timer(const Duration(milliseconds: 400), gate.complete);
        }
        final opened = await store.open(credential: credential);
        if (delayed && first) {
          first = false;
          stderr.writeln('test:opening');
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        return opened;
      },
    );
  } finally {
    await store.dispose();
    // Native fixture observes cleanup before the controlling PTY disappears.
    stderr.writeln('test:closed');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
