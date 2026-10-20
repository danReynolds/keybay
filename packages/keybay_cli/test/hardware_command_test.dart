import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngineTestProbe;
import 'package:keybay_cli/src/application.dart';
import 'package:keybay_cli/src/auth_terminal.dart';
import 'package:keybay_cli/src/command.dart';
import 'package:keybay_cli/src/lifetime.dart';
import 'package:keybay_cli/src/manifest.dart';
import 'package:keybay_cli/src/process_executor.dart';
import 'package:keybay_cli/src/secret_input.dart';
import 'package:test/test.dart';
import '../../keybay/test/support/v2_passkey_backend.dart';
import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  late TestPasskeyProvider provider;
  late V2TestKeybay store;
  late _Terminal terminal;
  late CommandLifetime lifetime;
  final inputs = <Uint8List>[];
  final sessions = <KeybaySession>[];
  late StringBuffer output;
  late List<AuthMethod> methods;
  setUp(() async {
    inputs.clear();
    sessions.clear();
    provider = TestPasskeyProvider();
    store = V2TestKeybay(
      keypassClient: provider.client,
      probe: V2StoreEngineTestProbe(onOperationInput: inputs.add),
    );
    terminal = _Terminal();
    lifetime = CommandLifetime();
    output = StringBuffer();
    final seed = await store.open();
    await seed.set('test/marker', 'retained');
    await seed.auth.add(
      const PasskeyCredential.hardware(rpId: 'commands.test'),
      label: 'Primary',
    );
    await seed.auth.add(
      const PasskeyCredential.hardware(rpId: 'commands.test'),
      label: 'Backup',
    );
    methods = await seed.auth.list();
    await seed.close();
    inputs.clear();
  });
  tearDown(() async {
    for (final session in sessions) {
      await session.close();
    }
    provider.expectReleased();
    for (final bytes in inputs) {
      expect(bytes, everyElement(0));
    }
    await lifetime.close();
    await store.dispose();
    provider.clear();
  });
  CliApplication app({SessionOpener? opener}) => CliApplication(
    loadManifest: (_) async => Manifest({}),
    openSession:
        opener ??
        ({credential, methodId, cancellation}) async {
          final session = await store.open(
            credential: credential,
            methodId: methodId,
            cancellation: cancellation,
          );
          sessions.add(session);
          return session;
        },
    readSecretValue: ({required key, required fromStdin}) async =>
        utf8.encode('new value'),
    readPassphrase: ({summary}) async => utf8.encode('phrase'),
    authorizeSecretOutput: () {},
    authorizeSecretInput: ({required fromStdin}) {},
    lifetime: lifetime,
    commandExecutor: _Executor(),
    parentEnvironment: {},
    stdout: output,
    stderr: StringBuffer(),
    showLaunchSummary: (_) {},
    authTerminal: terminal,
  );

  test(
    'chooses an exact enrollment under the same RP without enrollment on open',
    () async {
      terminal.selection = 1;
      final expectedId = provider.registrations
          .firstWhere((request) => request.label == methods[1].label)
          .userId;
      expect(await app().execute(const ListCommand()), 0);
      expect(output.toString(), 'test/marker\n');
      expect(terminal.chosen!.id, methods[1].id);
      expect(provider.evaluations.last.userId, expectedId);
      expect(provider.registrations.length, 2);
      expect(terminal.closed, isTrue);
      expect(sessions.every((s) => s.isClosed), isTrue);
    },
  );
  test(
    'PIN-required prompts once and clears the input before returning',
    () async {
      provider.nextFailure = PasskeyErrorCode.pinRequired;
      final before = provider.operationCount;
      expect(await app().execute(const GetCommand('test/marker')), 0);
      expect(output.toString(), 'retained\n');
      expect(terminal.pinReads, 1);
      expect(terminal.pin, everyElement(0));
      expect(provider.operationCount, before + 2);
    },
  );
  test('rejected PIN exits without automatic retry', () async {
    provider.nextFailure = PasskeyErrorCode.pinRequired;
    terminal.onPin = () => provider.nextFailure = PasskeyErrorCode.pinInvalid;
    final before = provider.operationCount;
    expect(await app().execute(const ListCommand()), 1);
    expect(output.isEmpty, isTrue);
    expect(provider.operationCount, before + 2);
    expect(terminal.pinReads, 1);
    expect(terminal.pin, everyElement(0));
    expect(terminal.closed, isTrue);
  });
  test(
    'terminal cleanup failure closes a successfully opened session',
    () async {
      terminal.failClose = true;
      await expectLater(app().execute(const ListCommand()), throwsStateError);
      expect(sessions.single.isClosed, isTrue);
      expect(output.isEmpty, isTrue);
    },
  );
  test('cancellation reaches the provider and waits for drain', () async {
    final entered = Completer<void>(),
        stopped = Completer<void>(),
        release = Completer<void>();
    provider.beforeEvaluation = (signal) async {
      final sub = signal.onCancel.listen((_) => stopped.complete());
      entered.complete();
      try {
        await release.future;
      } finally {
        await sub.cancel();
      }
    };
    final running = app().execute(const ListCommand());
    await entered.future;
    lifetime.cancel();
    await stopped.future;
    var settled = false;
    final check = expectLater(
      running,
      throwsA(isA<CommandInterrupted>()),
    ).then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    expect(terminal.closed, isFalse);
    release.complete();
    await check;
    expect(terminal.closed, isTrue);
    expect(output.isEmpty, isTrue);
  });
  test('cancelled late open is closed before any record is printed', () async {
    final normal = app().openSession;
    final application = app(
      opener: ({credential, methodId, cancellation}) async {
        final result = await normal(
          credential: credential,
          methodId: methodId,
          cancellation: cancellation,
        );
        if (credential != null) lifetime.cancel();
        return result;
      },
    );
    await expectLater(
      application.execute(const ListCommand()),
      throwsA(isA<CommandInterrupted>()),
    );
    expect(sessions.single.isClosed, isTrue);
    expect(output.isEmpty, isTrue);
  });
  test('PIN decoder rejects malformed UTF8, controls, length and newline', () {
    for (final bytes in [
      [1, 2, 3],
      [0, 1, 2, 3],
      [255, 255, 255, 255],
      [65, 66, 67, 10],
      [65, 66, 67, 13],
      List.filled(64, 65),
    ]) {
      expect(
        () => decodeHardwarePinBytes(bytes),
        throwsA(isA<SecretInputException>()),
      );
    }
    expect(decodeHardwarePinBytes(utf8.encode('1234')), utf8.encode('1234'));
  });
}

final class _Terminal implements AuthTerminal, HardwarePrompt {
  int selection = 0, pinReads = 0;
  PasskeyMethod? chosen;
  final pin = utf8.encode('test-pin');
  void Function()? onPin;
  bool closed = false, failClose = false;
  @override
  final cancellation = PasskeyCancellation();
  @override
  Future<AuthMethod> chooseMethod(
    List<AuthMethod> methods, {
    String? summary,
  }) async => methods[selection];
  @override
  Future<HardwarePrompt> hardware(
    PasskeyMethod method, {
    String? summary,
  }) async {
    chosen = method;
    return this;
  }

  @override
  Future<Uint8List> readPin() async {
    pinReads++;
    onPin?.call();
    return pin;
  }

  @override
  void check() {}
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (failClose) throw StateError('test cleanup failure');
  }
}

final class _Executor implements CommandExecutor {
  @override
  PreparedCommand prepare({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
  }) => throw UnimplementedError();
  @override
  Future<int> execute({
    required PreparedCommand command,
    required Map<String, String> overlay,
  }) => throw UnimplementedError();
}
