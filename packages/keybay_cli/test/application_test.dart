import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/application.dart';
import 'package:keybay_cli/src/command.dart';
import 'package:keybay_cli/src/manifest.dart';
import 'package:keybay_cli/src/process_executor.dart';
import 'package:keybay_cli/src/lifetime.dart';
import 'package:keybay_cli/src/secret_input.dart';
import 'package:keybay_cli/src/secret_output.dart';
import 'package:keybay_cli/src/failure.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  test('help and version are compact and never open Keybay', () async {
    final harness = _Harness();
    final output = StringBuffer();
    final application = _application(harness: harness, stdout: output);

    expect(await application.execute(const HelpCommand()), exitSuccess);
    expect(output.toString(), isNot(contains('doctor')));
    expect(output.toString(), contains('get KEY'));
    expect(harness.openCalls, 0);

    output.clear();
    expect(await application.execute(const VersionCommand()), exitSuccess);
    expect(output.toString(), '$cliVersion\n');
    expect(harness.openCalls, 0);
  });

  test('set preflight rejects a value channel before SDK access', () async {
    final harness = _Harness();
    final app = _application(
      harness: harness,
      authorizeSecretInput: ({required fromStdin}) =>
          throw const SecretInputException('refused'),
    );
    await expectLater(
      app.execute(const SetCommand(key: 'acme/key', readFromStdin: true)),
      throwsA(isA<SecretInputException>()),
    );
    expect(harness.openCalls, 0);
  });

  test(
    'launch preparation fails before authentication or secret access',
    () async {
      final harness = _Harness();
      final executor = _FakeCommandExecutor()
        ..onPrepare = () =>
            throw CliFailure(exitCode: 127, lines: ['command not found']);
      final app = _application(
        harness: harness,
        executor: executor,
        manifest: Manifest({'TOKEN': const SecretManifestValue('acme/key')}),
      );
      expect(
        await app.execute(
          RunCommand(
            manifestPath: 'manifest',
            executable: 'tool',
            arguments: [],
          ),
        ),
        127,
      );
      expect(harness.openCalls, 0);
      expect(executor.calls, isEmpty);
    },
  );

  test(
    'protected run approves frozen inherited target before the one credential attempt',
    () async {
      final harness = _Harness();
      await harness.seed({'acme/key': utf8.encode('secret-sentinel')});
      await harness.protect('correct');
      final executor = _FakeCommandExecutor();
      var prompts = 0;
      final app = _application(
        harness: harness,
        executor: executor,
        parentEnvironment: {'PATH': '/inherited'},
        manifest: Manifest({
          'TOKEN': const SecretManifestValue('acme/key'),
          'ALIAS': const SecretManifestValue('acme/key'),
          'PATH': const LiteralManifestValue('/manifest-secret'),
          'LD_PRELOAD': const LiteralManifestValue('literal-sentinel'),
        }),
        passphraseReader: ({summary}) async {
          prompts++;
          expect(harness.credentialOpenCalls, 0);
          expect(harness.getManyCalls, 0);
          expect(executor.preparedEnvironment['PATH'], '/inherited');
          expect(summary, contains('"/resolved/tool"'));
          expect(summary, contains('TOKEN <- acme/key'));
          expect(summary, contains('PATH (literal) [affects execution]'));
          expect(summary, contains(r'\u{1b}'));
          expect(summary, contains(r'\u{202e}'));
          for (final secret in [
            'secret-sentinel',
            'literal-sentinel',
            '/manifest-secret',
          ]) {
            expect(summary, isNot(contains(secret)));
          }
          return utf8.encode('correct');
        },
      );
      expect(
        await app.execute(
          RunCommand(
            manifestPath: 'manifest\u202e',
            executable: 'tool',
            arguments: ['arg\u001b[31m'],
          ),
        ),
        0,
      );
      expect(prompts, 1);
      expect(harness.credentialOpenCalls, 1);
      expect(harness.getManyCalls, 1);
      expect(executor.calls.single.command.path, '/resolved/tool');
      expect(executor.calls.single.overlay['PATH'], '/manifest-secret');
      expect(harness.allSessionsClosed, isTrue);
    },
  );

  test(
    'foreground loss after get clears the result and reveals nothing',
    () async {
      final harness = _Harness();
      await harness.seed({'acme/key': utf8.encode('sentinel')});
      final output = StringBuffer();
      var checks = 0;
      final app = _application(
        harness: harness,
        stdout: output,
        authorizeSecretOutput: () {
          if (++checks == 2) throw const SecretOutputException('lost');
        },
      );
      await expectLater(
        app.execute(const GetCommand('acme/key')),
        throwsA(isA<SecretOutputException>()),
      );
      expect(output.toString(), isEmpty);
      expect(harness.returnedValueBuffers, everyElement(_isZeroed));
      expect(harness.allSessionsClosed, isTrue);
    },
  );

  test(
    'late open after interruption is awaited and closed without a record operation',
    () async {
      final harness = _Harness();
      final lifetime = CommandLifetime();
      final opened = Completer<void>();
      final resume = Completer<void>();
      final app = _application(
        harness: harness,
        lifetime: lifetime,
        opener: ({credential}) async {
          final session = await harness.open(credential: credential);
          opened.complete();
          await resume.future;
          return session;
        },
      );
      final running = app.execute(const ListCommand());
      await opened.future;
      lifetime.cancel();
      var settled = false;
      final checking = expectLater(
        running,
        throwsA(isA<CommandInterrupted>()),
      ).then((_) => settled = true);
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      resume.complete();
      await checking;
      expect(harness.listKeysCalls, 0);
      expect(harness.allSessionsClosed, isTrue);
    },
  );

  test(
    'late read after interruption clears bytes and never launches',
    () async {
      final harness = _Harness();
      await harness.seed({'acme/key': utf8.encode('sentinel')});
      final lifetime = CommandLifetime();
      harness.afterMany = () async {
        lifetime.cancel();
      };
      final executor = _FakeCommandExecutor();
      final app = _application(
        harness: harness,
        lifetime: lifetime,
        executor: executor,
        manifest: Manifest({'TOKEN': const SecretManifestValue('acme/key')}),
      );
      await expectLater(
        app.execute(
          RunCommand(
            manifestPath: 'manifest',
            executable: 'tool',
            arguments: [],
          ),
        ),
        throwsA(isA<CommandInterrupted>()),
      );
      expect(executor.calls, isEmpty);
      expect(harness.returnedValueBuffers, everyElement(_isZeroed));
      expect(harness.allSessionsClosed, isTrue);
    },
  );

  test('interruption before set prevents mutation and clears input', () async {
    final harness = _Harness();
    final lifetime = CommandLifetime();
    final value = utf8.encode('sentinel');
    final app = _application(
      harness: harness,
      lifetime: lifetime,
      valueReader: ({required key, required fromStdin}) async {
        lifetime.cancel();
        return value;
      },
    );
    await expectLater(
      app.execute(const SetCommand(key: 'acme/key', readFromStdin: true)),
      throwsA(isA<CommandInterrupted>()),
    );
    final session = await harness.store.open();
    expect(await session.contains('acme/key'), isFalse);
    await session.close();
    expect(value, _isZeroed);
    expect(harness.allSessionsClosed, isTrue);
  });

  test(
    'interruption after submitted set waits for commit without success or retry',
    () async {
      final harness = _Harness();
      final lifetime = CommandLifetime();
      harness.afterSet = () async {
        lifetime.cancel();
      };
      final errors = StringBuffer();
      final app = _application(
        harness: harness,
        lifetime: lifetime,
        stderr: errors,
      );
      await expectLater(
        app.execute(const SetCommand(key: 'acme/key', readFromStdin: true)),
        throwsA(isA<CommandInterrupted>()),
      );
      final session = await harness.store.open();
      expect(await session.get('acme/key'), 'secret-value');
      await session.close();
      expect(errors.toString(), isNot(contains('Stored')));
      expect(harness.allSessionsClosed, isTrue);
    },
  );

  test(
    'platform-only run shows its launch summary before reading values',
    () async {
      final harness = _Harness();
      await harness.seed({'acme/key': utf8.encode('secret-sentinel')});
      final shown = <String>[];
      var readsBeforeSummary = -1;
      final app = _application(
        harness: harness,
        manifest: Manifest({
          'TOKEN': const SecretManifestValue('acme/key'),
          'NODE_OPTIONS': const LiteralManifestValue('--require=./x.js'),
        }),
        showLaunchSummary: (summary) {
          shown.add(summary);
          readsBeforeSummary = harness.getManyCalls;
        },
      );
      expect(
        await app.execute(
          RunCommand(
            manifestPath: 'manifest',
            executable: 'tool',
            arguments: [],
          ),
        ),
        exitSuccess,
      );
      expect(shown, hasLength(1));
      expect(readsBeforeSummary, 0);
      expect(shown.single, contains('TOKEN <- acme/key'));
      expect(
        shown.single,
        contains('NODE_OPTIONS (literal) [affects execution]'),
      );
      expect(shown.single, isNot(contains('secret-sentinel')));
      expect(shown.single, isNot(contains('./x.js')));
    },
  );

  test('protected run shows its summary only with the prompt', () async {
    final harness = _Harness();
    await harness.seed({'acme/key': utf8.encode('secret-sentinel')});
    await harness.protect('correct');
    final shown = <String>[];
    var prompted = 0;
    final app = _application(
      harness: harness,
      manifest: Manifest({'TOKEN': const SecretManifestValue('acme/key')}),
      passphraseReader: ({summary}) async {
        prompted++;
        expect(summary, contains('TOKEN <- acme/key'));
        return Uint8List.fromList(utf8.encode('correct'));
      },
      showLaunchSummary: shown.add,
    );
    expect(
      await app.execute(
        RunCommand(manifestPath: 'manifest', executable: 'tool', arguments: []),
      ),
      exitSuccess,
    );
    expect(prompted, 1);
    expect(shown, isEmpty);
  });

  test('execution-affecting names cover common injection variables', () {
    for (final name in [
      'PATH',
      'LD_PRELOAD',
      'DYLD_INSERT_LIBRARIES',
      'NODE_OPTIONS',
      'BASH_ENV',
      'PYTHONSTARTUP',
      'GIT_SSH_COMMAND',
      'npm_config_node_options',
      'JAVA_TOOL_OPTIONS',
    ]) {
      expect(affectsExecutionName(name), isTrue, reason: name);
    }
    for (final name in ['API_URL', 'OPENAI_API_KEY', 'PORT', 'HOME']) {
      expect(affectsExecutionName(name), isFalse, reason: name);
    }
  });

  group('run', () {
    test('literal-only manifest never opens Keybay', () async {
      final harness = _Harness();
      final executor = _FakeCommandExecutor();
      final application = _application(
        harness: harness,
        executor: executor,
        parentEnvironment: const <String, String>{'PARENT': 'kept'},
        manifest: Manifest(<String, ManifestValue>{
          'URL': const LiteralManifestValue('https://example.test'),
          'EMPTY': const LiteralManifestValue(''),
        }),
      );

      expect(
        await application.execute(
          RunCommand(
            manifestPath: '.env',
            executable: '/usr/bin/true',
            arguments: const <String>[],
          ),
        ),
        exitSuccess,
      );
      expect(harness.openCalls, 0);
      expect(executor.calls.single.overlay, <String, String>{
        'URL': 'https://example.test',
        'EMPTY': '',
      });
      expect(executor.preparedEnvironment['PARENT'], 'kept');
    });

    test(
      'requests only distinct manifest references in one operation',
      () async {
        final harness = _Harness();
        await harness.seed(<String, List<int>>{
          'acme/api': utf8.encode('api-value'),
          'acme/shared': utf8.encode('shared-value'),
          'unreferenced/value': utf8.encode('must-not-read'),
        });
        final executor = _FakeCommandExecutor();
        final application = _application(
          harness: harness,
          executor: executor,
          manifest: Manifest(<String, ManifestValue>{
            'API': const SecretManifestValue('acme/api'),
            'API_ALIAS': const SecretManifestValue('acme/api'),
            'SHARED': const SecretManifestValue('acme/shared'),
            'LITERAL': const LiteralManifestValue('text'),
          }),
        );

        expect(
          await application.execute(
            RunCommand(
              manifestPath: '.env',
              executable: '/usr/bin/true',
              arguments: const <String>[],
            ),
          ),
          exitSuccess,
        );
        expect(harness.getManyCalls, 1);
        expect(harness.requestedKeys.single, <String>[
          'acme/api',
          'acme/shared',
        ]);
        expect(
          harness.requestedKeys.single,
          isNot(contains('unreferenced/value')),
        );
        expect(executor.calls.single.overlay, <String, String>{
          'API': 'api-value',
          'API_ALIAS': 'api-value',
          'SHARED': 'shared-value',
          'LITERAL': 'text',
        });
        expect(harness.allSessionsClosed, isTrue);
        expect(harness.returnedValueBuffers, everyElement(_isZeroed));
      },
    );

    test('missing references return 3 and launch nothing', () async {
      final harness = _Harness();
      await harness.seed(<String, List<int>>{
        'acme/present': utf8.encode('present'),
      });
      final executor = _FakeCommandExecutor();
      final errors = StringBuffer();
      final application = _application(
        harness: harness,
        executor: executor,
        stderr: errors,
        manifest: Manifest(<String, ManifestValue>{
          'PRESENT': const SecretManifestValue('acme/present'),
          'MISSING': const SecretManifestValue('acme/missing'),
          'MISSING_AGAIN': const SecretManifestValue('acme/missing'),
        }),
      );

      expect(
        await application.execute(
          RunCommand(
            manifestPath: '.env',
            executable: 'must-not-launch',
            arguments: const <String>[],
          ),
        ),
        exitNotFound,
      );
      expect(executor.calls, isEmpty);
      expect(errors.toString(), contains('2 of 3 references'));
      expect(
        RegExp('keybay set acme/missing').allMatches(errors.toString()),
        hasLength(1),
      );
      expect(harness.returnedValueBuffers, everyElement(_isZeroed));
      expect(harness.allSessionsClosed, isTrue);
    });

    test('malformed manifests fail before opening Keybay', () async {
      final harness = _Harness();
      final application = _application(
        harness: harness,
        loadManifest: (_) =>
            throw const ManifestParseException('expected NAME=VALUE', line: 2),
      );
      expect(
        await application.execute(
          RunCommand(
            manifestPath: '.env',
            executable: '/usr/bin/true',
            arguments: const <String>[],
          ),
        ),
        exitUsage,
      );
      expect(harness.openCalls, 0);
    });
  });

  group('authentication lifecycle', () {
    test('protected command prompts once, authenticates, and closes', () async {
      final harness = _Harness();
      await harness.protect('correct horse battery staple');
      var promptCalls = 0;
      late Uint8List supplied;
      final application = _application(
        harness: harness,
        passphraseReader: ({summary}) async {
          promptCalls++;
          supplied = Uint8List.fromList(
            utf8.encode('correct horse battery staple'),
          );
          return supplied;
        },
      );

      expect(await application.execute(const ListCommand()), exitSuccess);
      expect(promptCalls, 1);
      expect(harness.openCalls, 2);
      expect(harness.credentialOpenCalls, 1);
      expect(supplied, _isZeroed);
      expect(harness.allSessionsClosed, isTrue);
    });

    test('wrong passphrase maps to 1 without creating a session', () async {
      final harness = _Harness();
      await harness.protect('correct');
      final errors = StringBuffer();
      final application = _application(
        harness: harness,
        stderr: errors,
        passphraseReader: ({summary}) async =>
            Uint8List.fromList(utf8.encode('wrong')),
      );

      expect(await application.execute(const ListCommand()), exitFailure);
      expect(errors.toString(), contains('authentication failed'));
      expect(harness.openCalls, 2);
      expect(harness.sessions, isEmpty);
    });

    test('platform-only access warns before reading a new value', () async {
      final harness = _Harness();
      final events = <String>[];
      final errors = _RecordingSink(events, 'warning');
      final application = _application(
        harness: harness,
        stderr: errors,
        valueReader: ({required key, required fromStdin}) async {
          events.add('value');
          return Uint8List.fromList(utf8.encode('secret'));
        },
      );

      expect(
        await application.execute(
          const SetCommand(key: 'acme/key', readFromStdin: true),
        ),
        exitSuccess,
      );
      expect(events.take(2), <String>['warning', 'value']);
      expect(harness.allSessionsClosed, isTrue);
    });

    test(
      'platform-only warning does not advertise a deferred command',
      () async {
        final harness = _Harness();
        final errors = StringBuffer();
        final application = _application(harness: harness, stderr: errors);

        expect(await application.execute(const ListCommand()), exitSuccess);
        expect(errors.toString(), contains('platform protection only'));
        expect(errors.toString(), isNot(contains('keybay open')));
      },
    );
  });

  group('record commands', () {
    test('set snapshots bytes, clears caller input, and closes', () async {
      final harness = _Harness();
      final value = Uint8List.fromList(utf8.encode('secret-value'));
      final application = _application(
        harness: harness,
        valueReader: ({required key, required fromStdin}) async => value,
      );

      expect(
        await application.execute(
          const SetCommand(key: 'acme/key', readFromStdin: true),
        ),
        exitSuccess,
      );
      expect(value, _isZeroed);
      final checking = await harness.store.open();
      expect(await checking.get('acme/key'), 'secret-value');
      await checking.close();
      expect(harness.allSessionsClosed, isTrue);
    });

    test('get reveals only one safe value and clears returned bytes', () async {
      final harness = _Harness();
      await harness.seed(<String, List<int>>{
        'acme/key': utf8.encode('revealed-value'),
        'acme/other': utf8.encode('must-not-print'),
      });
      final output = StringBuffer();
      var authorizationCalls = 0;
      final application = _application(
        harness: harness,
        stdout: output,
        authorizeSecretOutput: () => authorizationCalls++,
      );

      expect(
        await application.execute(const GetCommand('acme/key')),
        exitSuccess,
      );
      expect(authorizationCalls, 2);
      expect(output.toString(), 'revealed-value\n');
      expect(output.toString(), isNot(contains('must-not-print')));
      expect(harness.getBytesCalls, 1);
      expect(harness.returnedValueBuffers, everyElement(_isZeroed));
      expect(harness.allSessionsClosed, isTrue);
    });

    test('get authorizes output before opening the store', () async {
      final harness = _Harness();
      final application = _application(
        harness: harness,
        authorizeSecretOutput: () => throw StateError('refused'),
      );
      await expectLater(
        application.execute(const GetCommand('acme/key')),
        throwsA(isA<StateError>()),
      );
      expect(harness.openCalls, 0);
    });

    test('missing get returns 3 and prints no value', () async {
      final harness = _Harness();
      final output = StringBuffer();
      final errors = StringBuffer();
      final application = _application(
        harness: harness,
        stdout: output,
        stderr: errors,
      );
      expect(
        await application.execute(const GetCommand('acme/missing')),
        exitNotFound,
      );
      expect(output.toString(), isEmpty);
      expect(errors.toString(), contains('Key not found: acme/missing'));
      expect(harness.allSessionsClosed, isTrue);
    });

    test('get refuses all terminal controls without echoing value', () async {
      const sentinel = 'must-not-render';
      final harness = _Harness();
      await harness.seed(<String, List<int>>{
        'acme/control': utf8.encode('$sentinel\nsecond-line'),
      });
      final output = StringBuffer();
      final errors = StringBuffer();
      final application = _application(
        harness: harness,
        stdout: output,
        stderr: errors,
      );
      expect(
        await application.execute(const GetCommand('acme/control')),
        exitUsage,
      );
      expect(output.toString(), isEmpty);
      expect(errors.toString(), isNot(contains(sentinel)));
      expect(harness.returnedValueBuffers, everyElement(_isZeroed));
    });

    test('rm is idempotent and list emits names without values', () async {
      final harness = _Harness();
      await harness.seed(<String, List<int>>{
        'zeta/key': utf8.encode('never-print-this'),
        'acme/key': utf8.encode('also-hidden'),
      });
      final output = StringBuffer();
      final application = _application(harness: harness, stdout: output);

      expect(await application.execute(const RemoveCommand('zeta/key')), 0);
      expect(await application.execute(const RemoveCommand('zeta/key')), 0);
      expect(await application.execute(const ListCommand()), 0);
      expect(output.toString(), 'acme/key\n');
      expect(harness.listKeysCalls, 1);
      expect(harness.allSessionsClosed, isTrue);
    });
  });
}

CliApplication _application({
  required _Harness harness,
  Manifest? manifest,
  ManifestLoader? loadManifest,
  _FakeCommandExecutor? executor,
  StringBuffer? stdout,
  StringSink? stderr,
  Map<String, String> parentEnvironment = const <String, String>{},
  SecretValueReader? valueReader,
  PassphraseReader? passphraseReader,
  SecretOutputAuthorizer authorizeSecretOutput = _allowSecretOutput,
  void Function({required bool fromStdin})? authorizeSecretInput,
  CommandLifetime? lifetime,
  SessionOpener? opener,
  LaunchSummaryWriter? showLaunchSummary,
}) {
  addTearDown(harness.dispose);
  return CliApplication(
    loadManifest:
        loadManifest ??
        (_) async => manifest ?? Manifest(<String, ManifestValue>{}),
    openSession: opener ?? harness.open,
    readSecretValue:
        valueReader ??
        ({required key, required fromStdin}) async =>
            Uint8List.fromList(utf8.encode('secret-value')),
    readPassphrase:
        passphraseReader ??
        ({summary}) async =>
            Uint8List.fromList(utf8.encode('unused-passphrase')),
    authorizeSecretOutput: authorizeSecretOutput,
    authorizeSecretInput: authorizeSecretInput ?? ({required fromStdin}) {},
    lifetime: lifetime ?? CommandLifetime(),
    commandExecutor: executor ?? _FakeCommandExecutor(),
    parentEnvironment: parentEnvironment,
    stdout: stdout ?? StringBuffer(),
    stderr: stderr ?? StringBuffer(),
    showLaunchSummary: showLaunchSummary ?? (_) {},
  );
}

void _allowSecretOutput() {}

final class _Harness {
  final V2TestKeybay store = V2TestKeybay(
    applicationId: 'dev.keybay.cli-application-test',
  );
  final List<_TrackingSession> sessions = <_TrackingSession>[];
  final List<List<String>> requestedKeys = <List<String>>[];
  final List<Uint8List> returnedValueBuffers = <Uint8List>[];
  int openCalls = 0;
  int credentialOpenCalls = 0;
  int getManyCalls = 0;
  Future<void> Function()? afterMany;
  Future<void> Function()? afterSet;
  int getBytesCalls = 0;
  int listKeysCalls = 0;

  bool get allSessionsClosed => sessions.every((session) => session.isClosed);

  Future<KeybaySession> open({KeybayCredential? credential}) async {
    openCalls++;
    if (credential != null) credentialOpenCalls++;
    final delegate = await store.open(credential: credential);
    final tracked = _TrackingSession(this, delegate);
    sessions.add(tracked);
    return tracked;
  }

  Future<void> seed(Map<String, List<int>> values) async {
    final session = await store.open();
    for (final entry in values.entries) {
      await session.setBytes(entry.key, Uint8List.fromList(entry.value));
    }
    await session.close();
  }

  Future<void> protect(String passphrase) async {
    final session = await store.open();
    final bytes = Uint8List.fromList(utf8.encode(passphrase));
    try {
      await session.auth.add(PassphraseCredential(phrase: bytes));
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      await session.close();
    }
    sessions.clear();
    openCalls = 0;
  }

  Future<void> dispose() async {
    for (final session in sessions) {
      await session.close();
    }
    await store.dispose();
  }
}

final class _TrackingSession implements KeybaySession {
  _TrackingSession(this.owner, this.delegate);

  final _Harness owner;
  final KeybaySession delegate;

  @override
  KeybayAuthManager get auth => delegate.auth;

  @override
  bool get isClosed => delegate.isClosed;

  @override
  bool get wasInitialized => delegate.wasInitialized;

  @override
  Future<void> clearAll() => delegate.clearAll();

  @override
  Future<void> close() => delegate.close();

  @override
  Future<bool> contains(String key) => delegate.contains(key);

  @override
  Future<bool> delete(String key) => delegate.delete(key);

  @override
  Future<String?> get(String key) => delegate.get(key);

  @override
  Future<Uint8List?> getBytes(String key) async {
    owner.getBytesCalls++;
    final value = await delegate.getBytes(key);
    if (value != null) owner.returnedValueBuffers.add(value);
    return value;
  }

  @override
  Future<Map<String, Uint8List?>> getManyBytes(Iterable<String> keys) async {
    owner.getManyCalls++;
    final requested = keys.toList();
    owner.requestedKeys.add(requested);
    final values = await delegate.getManyBytes(requested);
    owner.returnedValueBuffers.addAll(values.values.whereType<Uint8List>());
    await owner.afterMany?.call();
    return values;
  }

  @override
  Future<List<String>> listKeys() {
    owner.listKeysCalls++;
    return delegate.listKeys();
  }

  @override
  Future<void> set(String key, String value) => delegate.set(key, value);

  @override
  Future<void> setBytes(String key, Uint8List value) async {
    await delegate.setBytes(key, value);
    await owner.afterSet?.call();
  }
}

final class _ExecutionCall {
  _ExecutionCall(this.command, Map<String, String> overlay)
    : overlay = Map.of(overlay);
  final PreparedCommand command;
  final Map<String, String> overlay;
}

final class _FakeCommandExecutor implements CommandExecutor {
  final List<_ExecutionCall> calls = [];
  Map<String, String> preparedEnvironment = {};
  void Function()? onPrepare;
  @override
  PreparedCommand prepare({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
  }) {
    preparedEnvironment = Map.of(environment);
    onPrepare?.call();
    return PreparedCommand(
      path: '/resolved/tool',
      arguments: [executable, ...arguments],
    );
  }

  @override
  Future<int> execute({
    required PreparedCommand command,
    required Map<String, String> overlay,
  }) async {
    calls.add(_ExecutionCall(command, overlay));
    return 0;
  }
}

final class _RecordingSink implements StringSink {
  _RecordingSink(this.events, this.event);

  final List<String> events;
  final String event;

  void _record() => events.add(event);

  @override
  void write(Object? object) => _record();

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _record();

  @override
  void writeCharCode(int charCode) => _record();

  @override
  void writeln([Object? object = '']) => _record();
}

final Matcher _isZeroed = everyElement(0);
