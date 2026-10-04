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
import 'package:test/test.dart';

import '../../keybay/test/support/v2_passkey_backend.dart';
import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  late TestPasskeyProvider provider;
  late V2TestKeybay store;
  final models = <TuiModel>[];
  final inputs = <Uint8List>[];
  TuiModel model() {
    final value = createNativeTuiModel(
      openSession: store.open,
      resetStore: store.reset,
      authorize: () {},
      onExit: () {},
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
      reopened.chooseUnlock(
        reopened.unlockMethods.firstWhere((item) => item.id == second.id),
      );
      await reopened.hardwareAttempt();
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
      survivor.chooseUnlock(survivor.unlockMethods.single);
      await survivor.hardwareAttempt();
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
    reopened.chooseUnlock(reopened.unlockMethods.single);
    await reopened.hardwareAttempt();
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
      await seed.close();
      final m = model();
      await m.open();
      m.chooseUnlock(m.unlockMethods.single);
      final entered = Completer<void>(), release = Completer<void>();
      provider.afterNextSecret = () {
        entered.complete();
        return release.future;
      };
      final attempt = m.hardwareAttempt();
      await entered.future;
      final cancelled = m.cancelHardware();
      release.complete();
      await attempt;
      await cancelled;
      expect(m.hasSession, isFalse);
      expect(m.view, TuiView.unlockMethods);
      m.chooseUnlock(m.unlockMethods.single);
      await m.hardwareAttempt();
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
      m.chooseUnlock(m.unlockMethods.single);
      await m.hardwareAttempt();
      expect(provider.operationCount, before);
      expect(m.hasSession, isFalse);
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'hardware unlock focuses its action on entry and retry at $size',
      () async {
        final seed = await store.open();
        await seed.auth.add(
          const PasskeyCredential.hardware(rpId: cliHardwareRpId),
        );
        await seed.close();
        final m = model();
        await m.open();
        final before = provider.operationCount;
        final tester = FleuryTester(
          viewportSize: size,
          clipboard: DiscardClipboard(),
        );
        addTearDown(tester.dispose);
        tester.pumpWidget(KeybayTui(model: m));
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(m.view, TuiView.hardwareUnlock);
        expect(provider.operationCount, before);
        provider.nextFailure = PasskeyErrorCode.deviceUnavailable;
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
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
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(m.view, TuiView.hardwareUnlock);
      expect(m.hardwareLabel, m.unlockMethods[1].label);
    });
  }
}
