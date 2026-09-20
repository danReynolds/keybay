import 'dart:io';
import 'dart:convert';

import 'package:keybay_cli/src/secret_input.dart';
import 'package:keybay_cli/src/lifetime.dart';

Future<void> main(List<String> arguments) async {
  final lifetime = CommandLifetime()..start();
  final reader = SecretInputReader.system(
    stdin: stdin,
    stderr: stderr,
    lifetime: lifetime,
  );
  var status = 0;
  try {
    final passphrase = await reader.readPassphrase();
    final passphraseLength = passphrase.length;
    if (arguments.contains('--verify-paste')) {
      final expected = utf8.encode('probe\r\n🔑\x03\t\x1b[31m\r\n');
      if (passphrase.length != expected.length ||
          Iterable<int>.generate(
            passphrase.length,
          ).any((i) => passphrase[i] != expected[i])) {
        throw StateError('synthetic paste bytes changed');
      }
      stdout.writeln('paste:exact');
    }
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
  } on CommandInterrupted catch (error) {
    status = error.exitCode;
  } on SecretInputException catch (error) {
    stderr.writeln('error: $error');
    status = error.interactionUnavailable ? 4 : 2;
  }
  await lifetime.close();
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
