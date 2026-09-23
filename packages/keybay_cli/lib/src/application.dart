import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';

import 'command.dart';
import 'environment.dart';
import 'failure.dart';
import 'manifest.dart';
import 'secret_output.dart';
import 'lifetime.dart';
import 'process_executor.dart';
import 'terminal.dart';

const int exitSuccess = 0;
const int exitFailure = 1;
const int exitUsage = 2;
const int exitNotFound = 3;
const int exitInteraction = 4;

typedef ManifestLoader = Future<Manifest> Function(String path);
typedef SessionOpener =
    Future<KeybaySession> Function({KeybayCredential? credential});
typedef SecretValueReader =
    Future<Uint8List> Function({required String key, required bool fromStdin});
typedef PassphraseReader = Future<Uint8List> Function({String? summary});
typedef SecretOutputAuthorizer = void Function();
typedef LaunchSummaryWriter = void Function(String summary);

void _discardSummary(String summary) {}

final class CliApplication {
  CliApplication({
    required this.loadManifest,
    required this.openSession,
    required this.readSecretValue,
    required this.readPassphrase,
    required this.authorizeSecretOutput,
    required this.authorizeSecretInput,
    required this.lifetime,
    required this.commandExecutor,
    required Map<String, String> parentEnvironment,
    required this.stdout,
    required this.stderr,
    this.showLaunchSummary = _discardSummary,
  }) : parentEnvironment = Map<String, String>.unmodifiable(parentEnvironment);

  final ManifestLoader loadManifest;
  final SessionOpener openSession;
  final SecretValueReader readSecretValue;
  final PassphraseReader readPassphrase;
  final SecretOutputAuthorizer authorizeSecretOutput;
  final void Function({required bool fromStdin}) authorizeSecretInput;
  final CommandLifetime lifetime;
  final CommandExecutor commandExecutor;
  final Map<String, String> parentEnvironment;
  final StringSink stdout;
  final StringSink stderr;

  /// Shows a platform-only `run` its summary on the controlling terminal, if
  /// one is attached. It is visibility, not approval: nothing is awaited.
  final LaunchSummaryWriter showLaunchSummary;

  Future<int> execute(CliCommand command) async {
    try {
      lifetime.check();
      return switch (command) {
        HelpCommand() => _help(),
        VersionCommand() => _version(),
        RunCommand() => await _run(command),
        SetCommand() => await _set(command),
        GetCommand() => await _get(command),
        RemoveCommand() => await _remove(command),
        ListCommand() => await _list(),
        OpenCommand() => throw StateError(
          'Open must own the native terminal lifecycle.',
        ),
      };
    } on CliFailure catch (error) {
      error.writeTo(stderr);
      return error.exitCode;
    } on ManifestParseException catch (error) {
      stderr.writeln('error: invalid manifest: $error');
      stderr.writeln('Nothing was launched.');
      return exitUsage;
    } on FileSystemException {
      stderr.writeln('error: the manifest could not be read.');
      stderr.writeln('Check that the selected file exists and is readable.');
      stderr.writeln('Nothing was launched.');
      return exitUsage;
    } on StoredValueException catch (error) {
      stderr.writeln('error: $error.');
      stderr.writeln(
        'Store environment values as UTF-8 without NUL, or use the bytes-first '
        'Keybay library API outside the CLI.',
      );
      stderr.writeln(
        command is GetCommand
            ? 'Nothing was printed.'
            : 'Nothing was launched.',
      );
      return exitUsage;
    } on KeybayException catch (error) {
      final failure = failureForKeybay(error);
      failure.writeTo(stderr);
      return failure.exitCode;
    }
  }

  int _help() {
    stdout.write(cliHelp);
    return exitSuccess;
  }

  int _version() {
    stdout.writeln(cliVersion);
    return exitSuccess;
  }

  Future<int> _run(RunCommand command) async {
    final manifest = await loadManifest(command.manifestPath);
    lifetime.check();
    final prepared = commandExecutor.prepare(
      executable: command.executable,
      arguments: command.arguments,
      environment: parentEnvironment,
    );
    late final EnvironmentResolution resolution;
    final keys = _referencedKeys(manifest);
    if (keys.isEmpty) {
      resolution = resolveEnvironment(
        manifest: manifest,
        storedValues: const <String, Uint8List>{},
      );
    } else {
      resolution = await _withSession((session) async {
        final selected = await session.getManyBytes(keys);
        try {
          lifetime.check();
          return resolveEnvironment(
            manifest: manifest,
            storedValues: <String, Uint8List>{
              for (final entry in selected.entries)
                if (entry.value case final value?) entry.key: value,
            },
          );
        } finally {
          for (final value in selected.values) {
            _clear(value);
          }
        }
      }, summary: launchSummary(command.manifestPath, prepared, manifest));
    }

    lifetime.check();
    if (!resolution.isComplete) {
      _writeMissingReferences(command.manifestPath, resolution);
      return exitNotFound;
    }

    await lifetime.close();
    lifetime.check();
    return commandExecutor.execute(
      command: prepared,
      overlay: resolution.overlay,
    );
  }

  Future<int> _set(SetCommand command) async {
    authorizeSecretInput(fromStdin: command.readFromStdin);
    return _withSession((session) async {
      final value = await readSecretValue(
        key: command.key,
        fromStdin: command.readFromStdin,
      );
      try {
        lifetime.check();
        final writing = session.setBytes(command.key, value);
        _clear(value);
        await writing;
        lifetime.check();
      } finally {
        _clear(value);
      }
      stderr.writeln('Stored ${command.key}');
      return exitSuccess;
    });
  }

  Future<int> _get(GetCommand command) async {
    // Refuse an unsafe output channel before opening the store or learning
    // whether it is protected.
    authorizeSecretOutput();
    return _withSession((session) async {
      final bytes = await session.getBytes(command.key);
      try {
        lifetime.check();
        if (bytes == null) {
          stderr.writeln('Key not found: ${command.key}');
          return exitNotFound;
        }
        final value = decodeStoredValue(command.key, bytes);
        if (!secretIsSafeForTerminal(value)) {
          throw StoredValueException(
            command.key,
            'contains control or invisible characters that get cannot show '
            'faithfully; view it with keybay open',
          );
        }
        authorizeSecretOutput();
        lifetime.check();
        stdout.writeln(value);
        return exitSuccess;
      } finally {
        _clear(bytes);
      }
    });
  }

  Future<int> _remove(RemoveCommand command) => _withSession((session) async {
    await session.delete(command.key);
    lifetime.check();
    return exitSuccess;
  });

  Future<int> _list() => _withSession((session) async {
    final keys = (await session.listKeys()).toList()..sort();
    lifetime.check();
    for (final key in keys) {
      stdout.writeln(key);
    }
    return exitSuccess;
  });

  Future<T> _withSession<T>(
    Future<T> Function(KeybaySession) operation, {
    String? summary,
  }) async {
    KeybaySession? session;
    try {
      session = await _openAuthenticatedSession(summary: summary);
      lifetime.check();
      final methods = await session.auth.list();
      lifetime.check();
      if (methods.isEmpty) {
        stderr.writeln(
          'warning: platform protection only; no additional credential is '
          'configured.',
        );
        // A protected run showed this before its passphrase prompt; show a
        // platform-only run the same summary before any value is read.
        if (summary != null) showLaunchSummary(summary);
      }
      lifetime.check();
      return await operation(session);
    } finally {
      await session?.close();
    }
  }

  Future<KeybaySession> _openAuthenticatedSession({String? summary}) async {
    try {
      return await openSession();
    } on KeybayException catch (error) {
      if (error.code != KeybayErrorCode.authRequired) rethrow;
    }

    lifetime.check();
    final passphrase = await readPassphrase(summary: summary);
    try {
      lifetime.check();
      final opening = openSession(
        credential: PassphraseCredential(phrase: passphrase),
      );
      _clear(passphrase);
      return await opening;
    } finally {
      _clear(passphrase);
    }
  }

  void _writeMissingReferences(
    String manifestPath,
    EnvironmentResolution resolution,
  ) {
    final missing = resolution.missingReferenceCount;
    final total = resolution.referenceCount;
    final noun = missing == 1 ? 'reference' : 'references';
    stderr.writeln(
      'error: $missing of $total $noun in ${terminalQuoted(manifestPath)} '
      '${missing == 1 ? 'is' : 'are'} not set on this machine:',
    );
    stderr.writeln();
    for (final key in resolution.missingKeys) {
      stderr.writeln('  keybay set $key');
    }
    stderr.writeln();
    stderr.writeln('Nothing was launched.');
  }
}

List<String> _referencedKeys(Manifest manifest) {
  final result = <String>[];
  final seen = <String>{};
  for (final value in manifest.values.values) {
    if (value case SecretManifestValue(:final key)) {
      if (seen.add(key)) result.add(key);
    }
  }
  return result;
}

void _clear(Uint8List? bytes) {
  if (bytes != null) bytes.fillRange(0, bytes.length, 0);
}

/// All caller-controlled text is quoted, and values never enter this summary.
String launchSummary(
  String manifestPath,
  PreparedCommand command,
  Manifest manifest,
) {
  final text = StringBuffer()
    ..writeln(
      'Run: ${terminalQuoted(command.path)} ${command.arguments.skip(1).map(terminalQuoted).join(' ')}',
    )
    ..writeln('Manifest: ${terminalQuoted(manifestPath)}')
    ..writeln('Environment:');
  for (final entry in manifest.values.entries) {
    final affectsExecution = affectsExecutionName(entry.key);
    final kind = switch (entry.value) {
      LiteralManifestValue() => '(literal)',
      SecretManifestValue(:final key) => '<- $key',
    };
    text.writeln(
      '  ${entry.key} $kind${affectsExecution ? ' [affects execution]' : ''}',
    );
  }
  return text.toString();
}

/// Variables that can make the launched program, or one it runs, execute other
/// code. A highlight for review, not a complete list or a sandbox.
bool affectsExecutionName(String name) =>
    _executionNames.contains(name) ||
    _executionPrefixes.any(name.startsWith) ||
    name.toLowerCase().startsWith('npm_config_');

const Set<String> _executionNames = {
  'PATH',
  'BASH_ENV',
  'ENV',
  'ZDOTDIR',
  'PROMPT_COMMAND',
  'SHELLOPTS',
  'IFS',
  'NODE_OPTIONS',
  'NODE_PATH',
  'PERL5OPT',
  'PERL5LIB',
  'PERLLIB',
  'RUBYOPT',
  'RUBYLIB',
  'JAVA_TOOL_OPTIONS',
  '_JAVA_OPTIONS',
  'JDK_JAVA_OPTIONS',
  'CLASSPATH',
  'EDITOR',
  'VISUAL',
  'PAGER',
  'LESSOPEN',
  'SSH_ASKPASS',
  'SUDO_ASKPASS',
  'GCONV_PATH',
};

const List<String> _executionPrefixes = ['LD_', 'DYLD_', 'PYTHON', 'GIT_'];
