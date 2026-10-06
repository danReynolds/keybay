@Tags(['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngineTestProbe;
import 'package:keybay/src/v2/store_files.dart';
import 'package:keybay_cli/src/tui/clipboard.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';
import 'package:keybay_cli/src/tui/store.dart';
import 'package:keybay_cli/src/tui/unlock_preference.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_passkey_backend.dart';
import '../../keybay/test/support/v2_test_keybay.dart';

class _Preference implements UnlockPreference {
  _Preference([this.id]);
  String? id;
  bool fail = false;
  final writes = <String>[];

  @override
  Future<String?> read() async {
    if (fail) throw StateError('preference unavailable');
    return id;
  }

  @override
  Future<void> write(String methodId) async {
    if (fail) throw StateError('preference unavailable');
    writes.add(methodId);
    id = methodId;
  }
}

void main() {
  late TestPasskeyProvider provider;
  late V2TestKeybay store;
  final models = <TuiModel>[];
  final inputs = <Uint8List>[];
  TuiModel model({
    UnlockPreference? preference,
    Future<bool> Function(TuiCancellation)? connected,
    Duration connectionTimeout = const Duration(minutes: 2),
  }) {
    final value = createNativeTuiModel(
      openSession: store.open,
      resetStore: store.reset,
      authorize: () {},
      onExit: () {},
      unlockPreference: preference,
      hardwareConnected: connected,
      hardwarePollInterval: const Duration(milliseconds: 10),
      hardwareConnectionTimeout: connectionTimeout,
    );
    models.add(value);
    return value;
  }

  setUp(() async {
    inputs.clear();
    provider = TestPasskeyProvider();
    store = V2TestKeybay(
      keypassClient: provider.client,
      probe: V2StoreEngineTestProbe(onOperationInput: inputs.add),
    );
    final session = await store.open();
    await session.set('test/marker', 'retained');
    await session.close();
  });
  tearDown(() async {
    for (final m in models) {
      await m.close();
      m.dispose();
    }
    models.clear();
    await store.dispose();
    provider.expectReleased();
    provider.clear();
  });

  test(
    'enroll, reopen exact saved methods, remove one and keep its survivor',
    () async {
      final m = model();
      await m.open();
      m.navigate(TuiView.hardware);
      await m.hardwareAttempt(label: 'Primary key');
      expect(m.view, TuiView.security);
      final first = m.methods.single;
      expect(first.kind, TuiAuthKind.hardware);
      expect(first.rpId, cliHardwareRpId);
      m.navigate(TuiView.hardware);
      await m.hardwareAttempt(label: 'Backup enrollment');
      final second = m.methods.firstWhere((item) => item.id != first.id);
      await m.close();

      final reopened = model();
      final beforeOpen = provider.operationCount;
      await reopened.open();
      expect(reopened.view, TuiView.unlockMethods);
      expect(
        provider.operationCount,
        beforeOpen,
      ); // hints never enroll or unlock
      expect(reopened.unlockMethods, hasLength(2));
      await reopened.chooseUnlock(
        reopened.unlockMethods.firstWhere((item) => item.id == second.id),
      );
      expect(reopened.view, TuiView.browse);
      expect(provider.operationCount, beforeOpen + 1);
      expect(provider.registrations, hasLength(2));
      await reopened.read();
      expect(reopened.valueText, 'retained');
      reopened.selectMethod(
        reopened.methods.firstWhere((item) => item.id == first.id),
      );
      reopened.navigate(TuiView.removeMethod);
      await reopened.removeSelectedMethod();
      expect(reopened.methods.single.id, second.id);
      await reopened.close();
      final survivor = model();
      await survivor.open();
      expect(survivor.view, TuiView.browse);
      await survivor.read();
      expect(survivor.valueText, 'retained');
      survivor.selectMethod(survivor.methods.single);
      survivor.navigate(TuiView.removeMethod);
      await survivor.removeSelectedMethod();
      expect(survivor.methods, isEmpty);
      await survivor.close();
      final platform = await store.open();
      expect(await platform.get('test/marker'), 'retained');
      await platform.close();
    },
  );

  for (final code in [
    PasskeyErrorCode.pinRequired,
    PasskeyErrorCode.pinInvalid,
  ]) {
    test(
      '$code retains the session, clears PINs, and never retries itself',
      () async {
        final m = model();
        await m.open();
        m.navigate(TuiView.hardware);
        final generation = store.files.liveGeneration;
        final pin = utf8.encode('1234');
        inputs.clear();
        provider.nextFailure = code;
        final attempt = m.hardwareAttempt(pin: pin);
        expect(pin, everyElement(0));
        await attempt;
        expect(m.view, TuiView.hardware);
        expect(m.hasSession, isTrue);
        expect(m.hardwareNeedsPin, isTrue);
        expect(provider.operationCount, 1);
        expect(store.files.liveGeneration, generation);
        expect(m.methods, isEmpty);
        for (final copy in inputs) {
          expect(copy, everyElement(0));
        }
        await m.hardwareAttempt(pin: utf8.encode('1234'));
        expect(m.methods, hasLength(1));
        expect(provider.operationCount, 2);
      },
    );
  }

  for (final code in [
    PasskeyErrorCode.pinBlocked,
    PasskeyErrorCode.pinTemporarilyBlocked,
  ]) {
    test('$code prevents further submission on the current form', () async {
      final m = model();
      await m.open();
      m.navigate(TuiView.hardware);
      provider.nextFailure = code;
      await m.hardwareAttempt();
      expect(m.hardwareCanRetry, isFalse);
      final pin = utf8.encode('1234');
      await m.hardwareAttempt(pin: pin);
      expect(pin, everyElement(0));
      expect(provider.operationCount, 1);
      expect(m.methods, isEmpty);
    });
  }

  for (final code in [
    PasskeyErrorCode.deviceUnavailable,
    PasskeyErrorCode.deviceSelectionRequired,
    PasskeyErrorCode.prfUnavailable,
  ]) {
    test(
      '$code keeps the current policy and permits deliberate retry',
      () async {
        final m = model();
        await m.open();
        m.navigate(TuiView.hardware);
        final generation = store.files.liveGeneration;
        provider.nextFailure = code;
        await m.hardwareAttempt();
        expect(m.view, TuiView.hardware);
        expect(m.hasSession, isTrue);
        expect(m.hardwareCanRetry, isTrue);
        expect(m.hardwareError, isNotEmpty);
        expect(m.methods, isEmpty);
        expect(store.files.liveGeneration, generation);
        expect(provider.operationCount, 1);
      },
    );
  }

  for (final quitting in [false, true]) {
    test(
      'cancellation drains a pending enrollment (quit: $quitting)',
      () async {
        final m = model();
        await m.open();
        m.navigate(TuiView.hardware);
        final entered = Completer<void>(), release = Completer<void>();
        provider.afterNextSecret = () {
          entered.complete();
          return release.future;
        };
        final generation = store.files.liveGeneration;
        final attempting = m.hardwareAttempt(pin: utf8.encode('1234'));
        await entered.future;
        var settled = false;
        final stopping = (quitting ? m.close() : m.cancelHardware()).then(
          (_) => settled = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse);
        expect(m.busy, isTrue);
        // Submitting again while the first native operation drains is rejected.
        final secondPin = utf8.encode('1234');
        await m.hardwareAttempt(pin: secondPin);
        expect(secondPin, everyElement(0));
        expect(provider.operationCount, 1);
        release.complete();
        await attempting;
        await stopping;
        expect(store.files.liveGeneration, generation);
        expect(m.view, quitting ? TuiView.closing : TuiView.security);
        expect(m.methods, isEmpty);
        if (!quitting) {
          m.navigate(TuiView.hardware);
          await m.hardwareAttempt();
          expect(m.methods, hasLength(1));
        }
      },
    );
  }

  test('cancellation after commit reports the enrolled method', () async {
    final m = model();
    await m.open();
    m.navigate(TuiView.hardware);
    Future<void>? stopping;
    store.files.afterReplaceLive = () {
      store.files.afterReplaceLive = null;
      stopping = m.cancelHardware();
    };
    await m.hardwareAttempt();
    await stopping;
    expect(m.view, TuiView.security);
    expect(m.methods, hasLength(1));
    expect(m.status, 'Hardware key added before cancellation completed.');
    expect(provider.operationCount, 1);
  });

  test('ambiguous commit closes and requires reopening to inspect', () async {
    final m = model();
    await m.open();
    m.navigate(TuiView.hardware);
    store.files.afterReplaceLive = () {
      store.files.afterReplaceLive = null;
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    };
    await m.hardwareAttempt();
    expect(m.view, TuiView.failed);
    expect(m.hasSession, isFalse);
    expect(provider.operationCount, 1);
    final reopened = model();
    await reopened.open();
    expect(reopened.unlockMethods, hasLength(1));
    expect(reopened.view, TuiView.browse);
    await reopened.read();
    expect(reopened.valueText, 'retained');
    expect(provider.registrations, hasLength(1));
  });

  test(
    'cancelled unlock closes a late result and permits deliberate retry',
    () async {
      final seed = model();
      await seed.open();
      seed.navigate(TuiView.hardware);
      await seed.hardwareAttempt();
      seed.navigate(TuiView.hardware);
      await seed.hardwareAttempt(label: 'Backup');
      await seed.close();
      final m = model();
      await m.open();
      final entered = Completer<void>(), release = Completer<void>();
      provider.afterNextSecret = () {
        entered.complete();
        return release.future;
      };
      final attempt = m.chooseUnlock(m.unlockMethods.first);
      await entered.future;
      final cancelled = m.cancelHardware();
      release.complete();
      await attempt;
      await cancelled;
      expect(m.hasSession, isFalse);
      expect(m.view, TuiView.unlockMethods);
      await m.chooseUnlock(m.unlockMethods.first);
      expect(m.hasSession, isTrue);
    },
  );

  test(
    'system-only methods are visible but never sent to the hardware route',
    () async {
      final seed = await store.open();
      await seed.auth.add(
        const PasskeyCredential.system(rpId: 'vault.example.com'),
      );
      await seed.close();
      final m = model();
      await m.open();
      final before = provider.operationCount;
      expect(m.view, TuiView.unlockMethods);
      await m.chooseUnlock(m.unlockMethods.single);
      await m.hardwareAttempt();
      expect(provider.operationCount, before);
      expect(m.hasSession, isFalse);
    },
  );

  Future<void> seedMethods({
    int hardware = 2,
    bool phrase = false,
    bool system = false,
  }) async {
    final session = await store.open();
    for (var i = 0; i < hardware; i++) {
      await session.auth.add(
        const PasskeyCredential.hardware(rpId: cliHardwareRpId),
        label: 'Key $i',
      );
    }
    if (phrase) {
      final bytes = utf8.encode('test-passphrase');
      try {
        await session.auth.add(PassphraseCredential(phrase: bytes));
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    if (system) {
      await session.auth.add(
        const PasskeyCredential.system(rpId: 'vault.example.com'),
        label: 'System key',
      );
    }
    await session.close();
  }

  test('remembers the exact successful key across model instances', () async {
    await seedMethods();
    final preference = _Preference();
    final first = model(preference: preference);
    final before = provider.operationCount;
    await first.open();
    expect(first.view, TuiView.unlockMethods);
    final selected = first.unlockMethods.last;
    await first.chooseUnlock(selected);
    expect(first.view, TuiView.browse);
    expect(preference.id, selected.id);
    expect(provider.operationCount, before + 1);
    await first.close();
    final next = model(preference: preference);
    await next.open();
    expect(next.view, TuiView.browse);
    expect(next.hardwareLabel, selected.label);
    expect(provider.operationCount, before + 2);
    expect(provider.registrations, hasLength(2));
  });

  test('remembers passphrase and leaving it stays in the chooser', () async {
    await seedMethods(hardware: 1, phrase: true);
    final preference = _Preference();
    final first = model(preference: preference);
    final before = provider.operationCount;
    await first.open();
    final phrase = first.unlockMethods.firstWhere(
      (method) => method.kind == TuiAuthKind.passphrase,
    );
    await first.chooseUnlock(phrase);
    await first.open(utf8.encode('test-passphrase'));
    expect(first.view, TuiView.browse);
    expect(preference.id, phrase.id);
    await first.close();
    final next = model(preference: preference);
    await next.open();
    expect(next.view, TuiView.unlock);
    expect(provider.operationCount, before);
    next.navigate(TuiView.unlockMethods);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(next.view, TuiView.unlockMethods);
    expect(preference.id, phrase.id);
  });

  test(
    'stale or unsupported preferences fall back to usable methods',
    () async {
      await seedMethods(system: true);
      final initial = model();
      await initial.open();
      final system = initial.unlockMethods.firstWhere(
        (method) => method.kind == TuiAuthKind.system,
      );
      final before = provider.operationCount;
      for (final id in ['f' * 32, system.id]) {
        final current = model(preference: _Preference(id));
        await current.open();
        expect(current.view, TuiView.unlockMethods);
        expect(provider.operationCount, before);
        await current.close();
      }
      await initial.chooseUnlock(initial.usableUnlockMethods.last);
      final removed = initial.methods.lastWhere(
        (method) => method.kind == TuiAuthKind.hardware,
      );
      initial.selectMethod(removed);
      initial.navigate(TuiView.removeMethod);
      await initial.removeSelectedMethod();
      final remaining = initial.methods.singleWhere(
        (method) => method.kind == TuiAuthKind.hardware,
      );
      await initial.close();
      final next = model(preference: _Preference(removed.id));
      await next.open();
      expect(next.view, TuiView.browse);
      expect(next.hardwareLabel, remaining.label);
    },
  );

  test('preference read and write failures never block unlock', () async {
    await seedMethods(hardware: 1);
    final current = model(preference: _Preference()..fail = true);
    await current.open();
    expect(current.view, TuiView.browse);
  });

  test('waits for insertion without attempting authentication', () async {
    await seedMethods(hardware: 1);
    var connected = false;
    final checked = Completer<void>();
    final current = model(
      connected: (_) async {
        if (!checked.isCompleted) checked.complete();
        return connected;
      },
    );
    final before = provider.operationCount;
    final opening = current.open();
    await checked.future;
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(current.view, TuiView.hardwareUnlock);
    expect(current.hardwarePhase, HardwarePhase.connecting);
    expect(provider.operationCount, before);
    connected = true;
    await opening;
    expect(current.view, TuiView.browse);
    expect(provider.operationCount, before + 1);
  });

  test('other methods cancels discovery and waits for it to drain', () async {
    await seedMethods();
    final hints = model();
    await hints.open();
    final preference = _Preference(hints.unlockMethods.first.id);
    await hints.close();
    final entered = Completer<void>(), stopped = Completer<void>();
    final release = Completer<void>();
    final current = model(
      preference: preference,
      connected: (signal) async {
        entered.complete();
        await signal.cancelled;
        stopped.complete();
        await release.future;
        return false;
      },
    );
    final before = provider.operationCount;
    final opening = current.open();
    await entered.future;
    var finished = false;
    final switching = current.cancelHardware().then((_) => finished = true);
    await stopped.future;
    expect(finished, isFalse);
    expect(current.busy, isTrue);
    release.complete();
    await switching;
    await opening;
    expect(current.view, TuiView.unlockMethods);
    expect(preference.writes, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(current.view, TuiView.unlockMethods);
    expect(provider.operationCount, before);
  });

  test('cancelling the only usable method quits', () async {
    await seedMethods(hardware: 1);
    final entered = Completer<void>();
    final current = model(
      connected: (signal) async {
        entered.complete();
        await signal.cancelled;
        return false;
      },
    );
    final opening = current.open();
    await entered.future;
    await current.cancelHardware();
    await opening;
    expect(current.ending, isTrue);
    expect(current.view, TuiView.closing);
    expect(current.hasSession, isFalse);
  });

  test('connection timeout stops discovery until deliberate retry', () async {
    await seedMethods(hardware: 1);
    var checks = 0;
    final current = model(
      connected: (_) async {
        checks++;
        return false;
      },
      connectionTimeout: const Duration(milliseconds: 15),
    );
    final before = provider.operationCount;
    await current.open();
    expect(current.hardwareError, contains('No key connected'));
    expect(current.hardwareCanRetry, isTrue);
    final stoppedAt = checks;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(checks, stoppedAt);
    expect(provider.operationCount, before);
  });

  test('PIN is a normal prompt; rejection requires fresh input', () async {
    await seedMethods();
    final hints = model();
    await hints.open();
    final preference = _Preference(hints.unlockMethods.last.id);
    await hints.close();
    var checks = 0;
    final current = model(
      preference: preference,
      connected: (_) async {
        checks++;
        return true;
      },
    );
    final before = provider.operationCount;
    provider.nextFailure = PasskeyErrorCode.pinRequired;
    await current.open();
    expect(current.hardwareNeedsPin, isTrue);
    expect(current.hardwareError, isNull);
    expect(checks, 1);
    provider.nextFailure = PasskeyErrorCode.pinInvalid;
    final pin = utf8.encode('1234');
    final attempt = current.hardwareAttempt(pin: pin);
    expect(pin, everyElement(0));
    await attempt;
    expect(current.hardwareError, contains('PIN was rejected'));
    expect(checks, 1);
    expect(preference.writes, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(provider.operationCount, before + 2);
    await current.cancelHardware();
    expect(current.view, TuiView.unlockMethods);
    expect(preference.writes, isEmpty);
  });

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'hardware unlock starts on entry and focuses a deliberate retry at $size',
      () async {
        final seed = await store.open();
        await seed.auth.add(
          const PasskeyCredential.hardware(rpId: cliHardwareRpId),
        );
        await seed.close();
        final m = model();
        final before = provider.operationCount;
        provider.nextFailure = PasskeyErrorCode.deviceUnavailable;
        await m.open();
        final tester = FleuryTester(
          viewportSize: size,
          clipboard: DiscardClipboard(),
        );
        addTearDown(tester.dispose);
        tester.pumpWidget(KeybayTui(model: m));
        await tester.settle();
        expect(m.view, TuiView.hardwareUnlock);
        expect(tester.renderToString(), contains('Try again'));
        expect(tester.renderToString(), isNot(contains('[Enter] Unlock')));
        expect(provider.operationCount, before + 1);
        expect(m.hardwareError, contains('No hardware key'));
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(provider.operationCount, before + 2);
        expect(m.view, TuiView.browse);
      },
    );

    test('hardware form keeps PIN and undo state private at $size', () async {
      final m = model();
      await m.open();
      m.navigate(TuiView.hardware);
      final tester = FleuryTester(
        viewportSize: size,
        clipboard: DiscardClipboard(),
      );
      addTearDown(tester.dispose);
      tester.pumpWidget(KeybayTui(model: m));
      await tester.settle();
      expect(tester.renderToString(), contains('Add hardware key'));
      expect(tester.renderToString(), contains('[Esc] Cancel'));
      provider.nextFailure = PasskeyErrorCode.pinRequired;
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(m.hardwareNeedsPin, isTrue);
      const pin = 's3cr3t42';
      tester.type(pin);
      await tester.settle();
      expect(tester.renderToString(), isNot(contains(pin)));
      expect(
        jsonEncode(tester.semantics().toInspectionJson()),
        isNot(contains(pin)),
      );
      expect(
        jsonEncode(tester.accessibilitySnapshot().toJson()),
        isNot(contains(pin)),
      );
      provider.nextFailure = PasskeyErrorCode.pinInvalid;
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.z, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      final textInputs = tester.find(byType(TextInput));
      for (final input in textInputs) {
        expect(
          (input.widget as TextInput).controller?.text,
          isNot(contains(pin)),
        );
      }
      expect(tester.clipboard.readInProcess(), isNull);
      expect(tester.renderToString(), contains('[Esc] Cancel'));
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      expect(m.view, TuiView.security);
    });

    test('method chooser escapes labels and fits at $size', () async {
      final seed = await store.open();
      for (var i = 0; i < 8; i++) {
        await seed.auth.add(
          const PasskeyCredential.hardware(rpId: cliHardwareRpId),
          label: 'key-$i\n\x1b[31m',
        );
      }
      await seed.close();
      final m = model();
      await m.open();
      final tester = FleuryTester(
        viewportSize: size,
        clipboard: DiscardClipboard(),
      );
      addTearDown(tester.dispose);
      tester.pumpWidget(KeybayTui(model: m));
      await tester.settle();
      expect(tester.renderToString(), contains(r'\n\u{1b}'));
      expect(tester.renderToString(), contains('[Esc] Quit'));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      provider.nextFailure = PasskeyErrorCode.pinRequired;
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(m.view, TuiView.hardwareUnlock);
      expect(m.hardwareLabel, m.unlockMethods[1].label);
    });
  }
}
