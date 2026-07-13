import 'dart:io';

import 'package:keyway_cli/src/command.dart';

void main(List<String> arguments) {
  try {
    final command = parseCommand(arguments);
    switch (command) {
      case HelpCommand():
        stdout.write(cliHelp);
      case VersionCommand():
        stdout.writeln(cliVersion);
      default:
        stderr.writeln('keyway: command implementation is in progress');
        exitCode = 70;
    }
  } on CliUsageException catch (error) {
    stderr.writeln('keyway: $error');
    stderr.writeln('Try keyway --help.');
    exitCode = 2;
  }
}
