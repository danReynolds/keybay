import 'dart:io';

import 'package:keybay_cli/src/secret_input.dart';

Future<void> main() async {
  final reader = SecretInputReader.system(stdin: stdin, stderr: stderr);
  var status = 0;
  try {
    final passphrase = await reader.readPassphrase();
    final passphraseLength = passphrase.length;
    passphrase.fillRange(0, passphrase.length, 0);
    var stdinLength = 0;
    await for (final bytes in stdin) {
      stdinLength += bytes.length;
    }
    stdout.writeln('passphrase-bytes:$passphraseLength');
    stdout.writeln('stdin-bytes:$stdinLength');
    await stdout.flush();
    // Keep the test terminal alive briefly so the parent can inspect ECHO
    // before Darwin revokes the synthetic controlling terminal on exit.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } on SecretInputException catch (error) {
    stderr.writeln('error: $error');
    status = error.interactionUnavailable ? 4 : 2;
  }
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
