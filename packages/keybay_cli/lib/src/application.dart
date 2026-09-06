import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';

import 'command.dart';
import 'environment.dart';
import 'failure.dart';
import 'manifest.dart';
import 'secret_output.dart';

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
typedef PassphraseReader = Future<Uint8List> Function();
typedef SecretOutputAuthorizer = void Function();

abstract interface class CommandExecutor {
  /// Replaces this process with [executable]. [environment] is the resolved
  /// string-level view (parent + manifest) used for the CLI's own lookups;
  /// [overlay] is exactly the manifest-named subset to materialize.
  Future<int> execute({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
    required Map<String, String> overlay,
  });
}

final class CliApplication {
  CliApplication({
    required this.loadManifest,
    required this.openSession,
    required this.readSecretValue,
    required this.readPassphrase,
    required this.authorizeSecretOutput,
    required this.commandExecutor,
    required Map<String, String> parentEnvironment,
    required this.stdout,
    required this.stderr,
  }) : parentEnvironment = Map<String, String>.unmodifiable(parentEnvironment);

  final ManifestLoader loadManifest;
  final SessionOpener openSession;
  final SecretValueReader readSecretValue;
  final PassphraseReader readPassphrase;
  final SecretOutputAuthorizer authorizeSecretOutput;
  final CommandExecutor commandExecutor;
  final Map<String, String> parentEnvironment;
  final StringSink stdout;
  final StringSink stderr;

  Future<int> execute(CliCommand command) async {
    try {
      return switch (command) {
        HelpCommand() => _help(),
        VersionCommand() => _version(),
        RunCommand() => await _run(command),
        SetCommand() => await _set(command),
        GetCommand() => await _get(command),
        RemoveCommand() => await _remove(command),
        ListCommand() => await _list(),
      };
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
    late final EnvironmentResolution resolution;
    final keys = _referencedKeys(manifest);
    if (keys.isEmpty) {
      resolution = resolveEnvironment(
        manifest: manifest,
        parentEnvironment: parentEnvironment,
        storedValues: const <String, Uint8List>{},
      );
    } else {
      resolution = await _withSession((session) async {
        final selected = await session.getManyBytes(keys);
        try {
          return resolveEnvironment(
            manifest: manifest,
            parentEnvironment: parentEnvironment,
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
      });
    }

    if (!resolution.isComplete) {
      _writeMissingReferences(command.manifestPath, resolution);
      return exitNotFound;
    }

    return commandExecutor.execute(
      executable: command.executable,
      arguments: command.arguments,
      environment: resolution.environment,
      overlay: resolution.overlay,
    );
  }

  Future<int> _set(SetCommand command) => _withSession((session) async {
    final value = await readSecretValue(
      key: command.key,
      fromStdin: command.readFromStdin,
    );
    try {
      final writing = session.setBytes(command.key, value);
      _clear(value);
      await writing;
    } finally {
      _clear(value);
    }
    if (!command.readFromStdin) {
      stderr.writeln('Stored ${command.key}');
    }
    return exitSuccess;
  });

  Future<int> _get(GetCommand command) async {
    // Refuse an unsafe output channel before opening the store or learning
    // whether it is protected.
    authorizeSecretOutput();
    return _withSession((session) async {
      final bytes = await session.getBytes(command.key);
      if (bytes == null) {
        stderr.writeln('Key not found: ${command.key}');
        return exitNotFound;
      }
      try {
        final value = decodeStoredValue(command.key, bytes);
        if (!secretIsSafeForTerminal(value)) {
          throw StoredValueException(
            command.key,
            'contains terminal control characters that cannot be revealed safely',
          );
        }
        stdout.writeln(value);
        return exitSuccess;
      } finally {
        _clear(bytes);
      }
    });
  }

  Future<int> _remove(RemoveCommand command) => _withSession((session) async {
    await session.delete(command.key);
    return exitSuccess;
  });

  Future<int> _list() => _withSession((session) async {
    final keys = (await session.listKeys()).toList()..sort();
    for (final key in keys) {
      stdout.writeln(key);
    }
    return exitSuccess;
  });

  Future<T> _withSession<T>(Future<T> Function(KeybaySession) operation) async {
    KeybaySession? session;
    try {
      session = await _openAuthenticatedSession();
      if ((await session.auth.list()).isEmpty) {
        stderr.writeln(
          'warning: platform protection only; no additional credential is '
          'configured.',
        );
      }
      return await operation(session);
    } finally {
      await session?.close();
    }
  }

  Future<KeybaySession> _openAuthenticatedSession() async {
    try {
      return await openSession();
    } on KeybayException catch (error) {
      if (error.code != KeybayErrorCode.authRequired) rethrow;
    }

    final passphrase = await readPassphrase();
    try {
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
      'error: $missing of $total $noun in $manifestPath '
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
