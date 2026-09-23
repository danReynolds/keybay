import 'dart:io';

import 'package:keybay/keybay.dart';

import 'application.dart';
import 'command.dart';
import 'manifest.dart';
import 'process_executor.dart';
import 'process_hardening.dart';
import 'secret_input.dart';
import 'secret_output.dart';
import 'lifetime.dart';
import 'tui/runner.dart';
import 'tui/model.dart' show tuiIdleTimeout, tuiIdleWarning;

Future<int> runKeybay(
  List<String> arguments, {
  SessionOpener openSession = Keybay.open,
  Future<void> Function() resetStore = Keybay.reset,
  Duration idleTimeout = tuiIdleTimeout,
  Duration idleWarning = tuiIdleWarning,
}) async {
  ProcessHardening.apply();
  final lifetime = CommandLifetime();
  try {
    final workingDirectory = Directory.current.path;
    final command = parseCommand(arguments);
    if (command is OpenCommand) {
      return await runTui(
        openSession: openSession,
        resetStore: resetStore,
        idleTimeout: idleTimeout,
        idleWarning: idleWarning,
      );
    }
    lifetime.start();
    final input = SecretInputReader.system(
      stdin: stdin,
      stderr: stderr,
      lifetime: lifetime,
    );
    final output = SecretOutputGuard.system();
    final application = CliApplication(
      loadManifest: (path) => readManifest(
        File(path.startsWith('/') ? path : '$workingDirectory/$path'),
      ),
      openSession: openSession,
      readSecretValue: input.read,
      readPassphrase: input.readPassphrase,
      authorizeSecretOutput: output.authorize,
      authorizeSecretInput: input.authorize,
      lifetime: lifetime,
      commandExecutor: SystemCommandExecutor(
        stderr: stderr,
        workingDirectory: workingDirectory,
      ),
      parentEnvironment: Platform.environment,
      stdout: stdout,
      stderr: stderr,
      showLaunchSummary: input.showSummary,
    );
    return await application.execute(command);
  } on CommandInterrupted catch (error) {
    stderr.writeln(
      'Interrupted. Submitted operations may have completed; reopen to inspect state.',
    );
    return error.exitCode;
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
  } finally {
    await lifetime.close();
  }
}
