import 'key.dart';

const String defaultManifestPath = './.env';
const String cliVersion = '0.2.0';

const String cliHelp = '''
Usage: keybay <command>

Commands:
  open                                Open the interactive vault
  run [-f FILE] -- COMMAND [ARGS...]  Load .env and run a command
  set [--stdin] KEY                   Store a secret
  get KEY                             Reveal a secret to the foreground TTY
  rm KEY                              Remove a secret
  list                                List key names

Global flags:
  --help                              Show this help
  --version                           Show the version
''';

sealed class CliCommand {
  const CliCommand();
}

final class HelpCommand extends CliCommand {
  const HelpCommand();
}

final class VersionCommand extends CliCommand {
  const VersionCommand();
}

final class RunCommand extends CliCommand {
  RunCommand({
    required this.manifestPath,
    required this.executable,
    required List<String> arguments,
  }) : arguments = List<String>.unmodifiable(arguments);

  final String manifestPath;
  final String executable;
  final List<String> arguments;
}

final class SetCommand extends CliCommand {
  const SetCommand({required this.key, required this.readFromStdin});

  final String key;
  final bool readFromStdin;
}

final class GetCommand extends CliCommand {
  const GetCommand(this.key);

  final String key;
}

final class RemoveCommand extends CliCommand {
  const RemoveCommand(this.key);

  final String key;
}

final class ListCommand extends CliCommand {
  const ListCommand();
}

final class OpenCommand extends CliCommand {
  const OpenCommand();
}

final class CliUsageException implements Exception {
  const CliUsageException(this.message);

  final String message;

  @override
  String toString() => message;
}

CliCommand parseCommand(List<String> arguments) {
  if (arguments.any((argument) => argument.contains('\u0000'))) {
    throw const CliUsageException('arguments must not contain NUL');
  }
  if (arguments.isEmpty) {
    throw const CliUsageException('a command is required');
  }
  if (arguments.length == 1 && arguments.first == '--help') {
    return const HelpCommand();
  }
  if (arguments.length == 1 && arguments.first == '--version') {
    return const VersionCommand();
  }

  return switch (arguments.first) {
    'run' => _parseRun(arguments),
    'set' => _parseSet(arguments),
    'get' => _parseGet(arguments),
    'rm' => _parseRemove(arguments),
    'list' when arguments.length == 1 => const ListCommand(),
    'open' when arguments.length == 1 => const OpenCommand(),
    'open' => throw const CliUsageException('command takes no arguments'),
    'list' => throw const CliUsageException('command takes no arguments'),
    _ => throw const CliUsageException('unknown command'),
  };
}

RunCommand _parseRun(List<String> arguments) {
  var index = 1;
  var manifestPath = defaultManifestPath;
  if (index < arguments.length && arguments[index] == '-f') {
    index++;
    if (index >= arguments.length || arguments[index].isEmpty) {
      throw const CliUsageException('run -f requires a file');
    }
    manifestPath = arguments[index];
    index++;
  }
  if (index >= arguments.length || arguments[index] != '--') {
    throw const CliUsageException('run requires -- before the command');
  }
  index++;
  if (index >= arguments.length || arguments[index].isEmpty) {
    throw const CliUsageException('run requires a command after --');
  }

  return RunCommand(
    manifestPath: manifestPath,
    executable: arguments[index],
    arguments: arguments.sublist(index + 1),
  );
}

SetCommand _parseSet(List<String> arguments) {
  final readFromStdin = arguments.length == 3 && arguments[1] == '--stdin';
  if ((!readFromStdin && arguments.length != 2) ||
      (readFromStdin && arguments.length != 3)) {
    throw const CliUsageException('usage: keybay set [--stdin] KEY');
  }

  final key = readFromStdin ? arguments[2] : arguments[1];
  _requireKey(key);
  return SetCommand(key: key, readFromStdin: readFromStdin);
}

GetCommand _parseGet(List<String> arguments) {
  if (arguments.length != 2) {
    throw const CliUsageException('usage: keybay get KEY');
  }
  final key = arguments[1];
  _requireKey(key);
  return GetCommand(key);
}

RemoveCommand _parseRemove(List<String> arguments) {
  if (arguments.length != 2) {
    throw const CliUsageException('usage: keybay rm KEY');
  }
  final key = arguments[1];
  _requireKey(key);
  return RemoveCommand(key);
}

void _requireKey(String key) {
  if (!isValidCliKey(key)) {
    throw const CliUsageException(
      'KEY must look like api-token or acme/api-token and be at most '
      '$cliKeyMaxLength characters',
    );
  }
}
