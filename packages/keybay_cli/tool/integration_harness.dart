import 'dart:io';
import 'dart:convert';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/entrypoint.dart';

Future<void> main(List<String> arguments) async {
  if (arguments case <String>['--test-reset']) {
    await Keybay.reset();
    return;
  }
  if (arguments case <String>['--test-protect']) {
    final session = await Keybay.open();
    final phrase = utf8.encode('disposable-passphrase');
    try {
      final change = session.auth.add(PassphraseCredential(phrase: phrase));
      phrase.fillRange(0, phrase.length, 0);
      await change;
    } finally {
      phrase.fillRange(0, phrase.length, 0);
      await session.close();
    }
    return;
  }
  final reportClose =
      arguments.isNotEmpty && arguments.first == '--test-command';
  final status = await runKeybay(
    reportClose ? arguments.sublist(1) : arguments,
  );
  if (reportClose) {
    stderr.writeln('test:closed');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
