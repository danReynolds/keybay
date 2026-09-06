import 'dart:io';

import 'package:keybay/keybay.dart';

import 'application.dart';
import 'command.dart';
import 'manifest.dart';
import 'process_executor.dart';
import 'secret_input.dart';
import 'secret_output.dart';

Future<int> runKeybay(List<String> arguments) async {
  try {
    final command = parseCommand(arguments);
    final input = SecretInputReader.system(stdin: stdin, stderr: stderr);
    final output = SecretOutputGuard.system();
    final application = CliApplication(
      loadManifest: (path) => readManifest(File(path)),
      openSession: Keybay.open,
      readSecretValue: input.read,
      readPassphrase: input.readPassphrase,
      authorizeSecretOutput: output.authorize,
      commandExecutor: SystemCommandExecutor(stderr: stderr),
      parentEnvironment: Platform.environment,
      stdout: stdout,
      stderr: stderr,
    );
    return await application.execute(command);
  } on CliUsageException catch (error) {
    stderr.writeln('keybay: $error');
    stderr.writeln('Try keybay --help.');
    return exitUsage;
  } on SecretInputException catch (error) {
    stderr.writeln('error: $error.');
    return error.interactionUnavailable ? exitInteraction : exitUsage;
  } on SecretOutputException catch (error) {
    stderr.writeln('error: $error.');
    return exitInteraction;
  } on UnsupportedError {
    stderr.writeln('error: this Keybay CLI operation is not qualified here.');
    return exitFailure;
  } on Object {
    stderr.writeln('error: an internal Keybay CLI invariant failed.');
    stderr.writeln('Report this bug upstream.');
    return exitFailure;
  }
}
