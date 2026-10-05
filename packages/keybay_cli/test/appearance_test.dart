@Tags(['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/appearance_file.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('keybay-appearance-');
    file = File('${directory.path}/ui/appearance.json');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('local preferences round-trip without reading a vault', () async {
    final preference = FileAppearancePreference(file);
    expect(await preference.read(), const TuiAppearance());
    const value = TuiAppearance(
      accent: TuiAccent.magenta,
      contrast: TuiContrast.high,
    );
    await preference.write(value);
    expect(await FileAppearancePreference(file).read(), value);
    expect(jsonDecode(await file.readAsString()), {
      'version': 1,
      'accent': 'magenta',
      'contrast': 'high',
    });
    await preference.write(const TuiAppearance());
    expect(await preference.read(), const TuiAppearance());
    expect(file.parent.listSync().map((f) => f.path), [file.path]);
  });

  test('bad preference data falls back without blocking startup', () async {
    await file.parent.create();
    for (final content in [
      '{',
      '[]',
      'null',
      'x' * 1025,
      '{"version":2,"accent":"blue"}',
      '{"version":1,"accent":{},"contrast":"unsupported"}',
    ]) {
      await file.writeAsString(content);
      expect(
        await FileAppearancePreference(file).read(),
        const TuiAppearance(),
      );
    }
    await file.writeAsString('{"version":1,"accent":"cyan","contrast":42}');
    expect(
      (await FileAppearancePreference(file).read()).accent,
      TuiAccent.cyan,
    );
  });

  test('a symlink is neither read nor overwritten', () async {
    await file.parent.create();
    final target = File('${directory.path}/unrelated');
    await target.writeAsString('untouched');
    await Link(file.path).create(target.path);
    final preference = FileAppearancePreference(file);
    expect(await preference.read(), const TuiAppearance());
    await expectLater(
      preference.write(const TuiAppearance()),
      throwsA(isA<FileSystemException>()),
    );
    expect(await target.readAsString(), 'untouched');
    expect(await Link(file.path).exists(), isTrue);
  }, skip: Platform.isWindows);

  test(
    'accent does not change warning or error meanings; contrast avoids dim',
    () {
      for (final accent in TuiAccent.values) {
        final theme = keybayThemeFor(
          TuiAppearance(accent: accent, contrast: TuiContrast.high),
        );
        expect(theme.colorScheme.foreground, isNull);
        expect(theme.colorScheme.background, isNull);
        expect(theme.colorScheme.warning, keybayColors.warning);
        expect(theme.colorScheme.error, keybayColors.error);
        expect(theme.colorScheme.success, keybayColors.success);
        expect(theme.mutedStyle.dim, isFalse);
        expect(theme.extension<KeybayAccents>()!.placeholder.dim, isFalse);
        expect(theme.selectionStyle.inverse, isTrue);
        expect(theme.errorStyle.underline, isTrue);
      }
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'appearance works by keyboard and click at $size, and survives reopening',
      () async {
        final store = V2TestKeybay();
        final preference = FileAppearancePreference(file);
        final session = await store.open();
        await session.set('sample/key', 'sample-value');
        await session.auth.add(
          PassphraseCredential(phrase: utf8.encode('sample')),
        );
        await session.close();
        final model = createNativeTuiModel(
          openSession: store.open,
          resetStore: store.reset,
          authorize: () {},
          onExit: () {},
          saveAppearance: preference.write,
        );
        final tester = FleuryTester(viewportSize: size);
        addTearDown(() async {
          tester.dispose();
          await model.close();
          model.dispose();
          await store.dispose();
        });
        await model.open();
        await model.open(Uint8List.fromList(utf8.encode('sample')));
        model.navigate(TuiView.settings);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.a));
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.arrowRight));
        await tester.settle();
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.radio, label: 'Green')
              .focused,
          isTrue,
        );
        tester.sendKey(const KeyEvent(KeyCode.arrowDown));
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(model.appearance.accent, TuiAccent.cyan);
        final high = tester.semantics().single(
          role: SemanticRole.radio,
          label: 'High',
        );
        expect(high.bounds!.bottom, lessThan(size.rows));
        for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
          tester.sendMouse(
            MouseEvent(
              kind: kind,
              button: MouseButton.left,
              col: high.bounds!.left,
              row: high.bounds!.top,
            ),
          );
        }
        await tester.settle();
        expect(model.appearance.contrast, TuiContrast.high);
        tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
        await tester.settle();
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.button, label: 'Appearance')
              .focused,
          isTrue,
        );
        expect(tester.renderToString(), isNot(contains('sample-value')));
        await model.close();

        final reopened = createNativeTuiModel(
          openSession: store.open,
          resetStore: store.reset,
          authorize: () {},
          onExit: () {},
          appearance: await preference.read(),
        );
        addTearDown(() async {
          await reopened.close();
          reopened.dispose();
        });
        await reopened.open();
        tester.pumpWidget(KeybayTui(model: reopened));
        await tester.settle();
        expect(reopened.view, TuiView.unlock);
        final lines = tester.renderToString(emptyMark: ' ').split('\n');
        final row = lines.indexWhere((line) => line.contains(' keybay '));
        final col = lines[row].indexOf('keybay');
        expect(lines[row], contains('┌'));
        expect(
          tester.render().atColRow(col, row).style.foreground,
          const AnsiColor(6),
        );
        expect(reopened.appearance.contrast, TuiContrast.high);
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.textField, label: 'Passphrase')
              .focused,
          isTrue,
        );
      },
    );
  }

  test(
    'save failure retains the choice and reports session-only state',
    () async {
      final model = TuiModel(
        openSession: ({phrase, method, pin, cancellation}) =>
            throw UnimplementedError(),
        resetStore: () async {},
        authorize: () {},
        onExit: () {},
        saveAppearance: (_) async => throw const FileSystemException('denied'),
      );
      addTearDown(model.dispose);
      model.setAppearance(const TuiAppearance(accent: TuiAccent.blue));
      await Future<void>.delayed(Duration.zero);
      expect(model.appearance.accent, TuiAccent.blue);
      expect(
        model.status,
        'Appearance changed for this session, but could not be saved.',
      );
      await model.close();
    },
  );

  test(
    'rapid choices save in order and close waits for the final choice',
    () async {
      final gate = Completer<void>();
      final values = <TuiAppearance>[];
      final model = TuiModel(
        openSession: ({phrase, method, pin, cancellation}) =>
            throw UnimplementedError(),
        resetStore: () async {},
        authorize: () {},
        onExit: () {},
        saveAppearance: (value) async {
          await gate.future;
          values.add(value);
        },
      );
      model.setAppearance(const TuiAppearance(accent: TuiAccent.blue));
      model.setAppearance(const TuiAppearance(accent: TuiAccent.magenta));
      var closed = false;
      final close = model.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      gate.complete();
      await close;
      expect(values.map((v) => v.accent), [TuiAccent.blue, TuiAccent.magenta]);
      model.dispose();
    },
  );
}
