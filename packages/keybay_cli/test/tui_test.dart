@Tags(['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/clipboard.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void expectFormActions(FleuryTester tester) {
  final screen = tester.renderToString(emptyMark: ' ');
  for (final action in ['[Ctrl+S] Save', '[Ctrl+R] Reveal', '[Esc] Cancel']) {
    expect(screen, contains(action));
  }
}

void main() {
  late V2TestKeybay store;
  late TuiModel model;
  late List<String> copied;
  late int exits;
  setUp(() async {
    store = V2TestKeybay();
    final session = await store.open();
    await session.set('acme/z', 'second-secret');
    await session.set('acme/a', 'first-secret\nnext line\r\n🔑\x1b[31m');
    await session.close();
    copied = [];
    exits = 0;
    model = createNativeTuiModel(
      openSession: store.open,
      resetStore: store.reset,
      authorize: () {},
      copyText: (text) async {
        copied.add(text);
      },
      onExit: () {
        exits++;
      },
    );
  });
  tearDown(() async {
    await model.close();
    model.dispose();
    await store.dispose();
  });

  test(
    'display measurement expires with disclosure and refreshes on reveal',
    () async {
      await model.open();
      await model.read();
      expect(model.valueDisplayWidth, longestEscapedLine(model.valueText));
      model.conceal();
      expect(model.valueText, isEmpty);
      expect(model.valueDisplayWidth, 0);

      final writer = await store.open();
      await writer.set('acme/a', '界界');
      await writer.close();
      await model.read();
      expect(model.valueDisplayWidth, 4);
      await model.read(edit: true);
      expect(model.takeEditText(), '界界');
      expect(model.valueText, isEmpty);
      expect(model.valueDisplayWidth, 0);
    },
  );

  test('theme roles resolve to the palette the design specifies', () {
    // Four roles are the framework's own and are read from ThemeData; only
    // these three are Keybay's to carry. Pin both so a scheme edit cannot
    // silently restyle the application.
    final accents = KeybayAccents.from(keybayColors);
    expect(
      accents.accent,
      const CellStyle(foreground: AnsiColor(2), bold: true),
    );
    expect(
      accents.attention,
      const CellStyle(foreground: AnsiColor(3), bold: true),
    );
    expect(
      accents.placeholder,
      const CellStyle(foreground: RgbColor(0x90, 0x90, 0x90)),
    );
    expect(
      keybayTheme.focusedStyle,
      const CellStyle(foreground: AnsiColor(6), bold: true),
    );
    expect(
      keybayTheme.errorStyle,
      const CellStyle(foreground: AnsiColor(9), bold: true),
    );
    expect(
      keybayTheme.selectionStyle,
      const CellStyle(
        foreground: RgbColor(0xa7, 0xd7, 0xb7),
        background: RgbColor(0x27, 0x3e, 0x31),
        bold: true,
      ),
    );
    // Left at the framework default rather than restated.
    expect(keybayTheme.mutedStyle, const CellStyle(dim: true));
    expect(keybayTheme.extension<KeybayAccents>(), isNotNull);
  });

  test('longestEscapedLine matches the width of the escaped value', () {
    // The vault sizes a revealed row from this instead of materialising the
    // escaped value on every frame; the two must not drift apart.
    int reference(String text) => safeTuiText(text)
        .split('\n')
        .fold(
          0,
          (widest, line) => max(
            widest,
            const DefaultWidthResolver().widthOfText(
              line,
              CellWidthPolicy.spec,
            ),
          ),
        );

    final random = Random(20260909);
    final alphabet = [
      ...List.generate(96, (i) => i + 31),
      0,
      1,
      9,
      10,
      13,
      27,
      0x7f,
      0xe9,
      0x2018,
      0x200e,
      0x202e,
      0xfeff,
      0x1f600,
      0x10ffff,
      0x4e2d,
      // Format, default-ignorable and zero-width cluster cases.
      0x0600,
      0x0301,
      0xfe0f,
      0x200c,
      0x3164,
      0xad,
      0xe0041,
    ];
    for (var trial = 0; trial < 2000; trial++) {
      final text = String.fromCharCodes([
        for (var i = random.nextInt(40); i > 0; i--)
          alphabet[random.nextInt(alphabet.length)],
      ]);
      expect(
        longestEscapedLine(text),
        reference(text),
        reason: text.codeUnits.toString(),
      );
    }
    for (final text in ['', '\n', '\n\n', 'a\n', '\na', r'\', 'a' * 500]) {
      expect(longestEscapedLine(text), reference(text));
    }
  });

  test('authenticate before names; failed phrase can retry', () async {
    final session = await store.open();
    await session.auth.add(PassphraseCredential(phrase: bytes('good')));
    await session.close();
    await model.open();
    expect(model.view, TuiView.unlock);
    expect(model.keys, isEmpty);
    final wrong = bytes('wrong');
    await model.open(wrong);
    expect(wrong, everyElement(0));
    expect(model.view, TuiView.unlock);
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.textField, label: 'Passphrase')
          .validationError,
      'Could not unlock. Check your passphrase and try again.',
    );
    expect(tester.semantics().where(role: SemanticRole.notification), isEmpty);
    await model.open(bytes('good'));
    await tester.settle();
    expect(model.status, isEmpty);
    expect(tester.semantics().where(role: SemanticRole.notification), isEmpty);
    expect(model.protected, isTrue);
    expect(model.keys, ['acme/a', 'acme/z']);
    expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
  });

  for (final protected in [false, true]) {
    test(
      'fast startup skips the opening panel (protected: $protected)',
      () async {
        if (protected) {
          final session = await store.open();
          await session.auth.add(PassphraseCredential(phrase: bytes('good')));
          await session.close();
        }
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        tester.pumpWidget(KeybayTui(model: model));
        expect(tester.renderToString(), contains('keybay'));
        expect(tester.renderToString(), isNot(contains('Opening Keybay')));
        final opening = model.open();
        tester.pump();
        expect(tester.renderToString(), isNot(contains('Opening Keybay')));
        await opening;
        await tester.settle();
        expect(model.view, protected ? TuiView.unlock : TuiView.browse);
        expect(tester.renderToString(), isNot(contains('Opening Keybay')));
        expect(model.showsBusy, isFalse);
      },
    );
  }

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'slow startup announces progress and still reaches unlock at $size',
      () async {
        final session = await store.open();
        await session.auth.add(PassphraseCredential(phrase: bytes('good')));
        await session.close();
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        store.gateNextOperation(gate.future);
        final opening = model.open();
        tester.pumpWidget(KeybayTui(model: model));
        expect(tester.renderToString(), isNot(contains('Opening Keybay')));
        await Future<void>.delayed(
          tuiBusyDelay + const Duration(milliseconds: 20),
        );
        tester.pump();
        expect(tester.renderToString(), contains('Opening Keybay'));
        expect(tester.renderToString(), contains('authorize access'));
        final quit = tester.semantics().single(
          role: SemanticRole.button,
          label: 'Quit',
        );
        expect(quit.bounds!.bottom, lessThanOrEqualTo(size.rows - 2));
        gate.complete();
        await opening;
        await tester.settle();
        expect(tester.renderToString(), contains('Unlock Keybay'));
        expect(tester.renderToString(), isNot(contains('Opening Keybay')));
        expect(model.showsBusy, isFalse);
      },
    );
  }

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test('unlock stays mounted through validation and retry at $size', () async {
      final session = await store.open();
      await session.auth.add(PassphraseCredential(phrase: bytes('good')));
      await session.close();
      await model.open();
      final tester = FleuryTester(viewportSize: size);
      addTearDown(tester.dispose);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final form = tester.find(byType(UnlockForm)).single;
      TextInput field() =>
          tester.find(byType(TextInput)).single.widget as TextInput;
      final focus = field().focusNode!;
      int actionRow() => tester
          .renderToString()
          .split('\n')
          .indexWhere((line) => line.contains('[Enter] Unlock'));
      final originalActionRow = actionRow();
      expect(originalActionRow, greaterThanOrEqualTo(0));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(field().validationError, 'Enter 1–1024 UTF-8 bytes.');
      expect(focus.hasFocus, isTrue);
      tester.type('wrong');
      await tester.settle();
      expect(field().validationError, isNull);
      final submittedDraft = field().controller!;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      store.gateNextOperation(gate.future);
      // Exercise the button path as well as Enter; a retry must focus the field.
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Unlock',
      );
      tester.pump();
      expect(model.view, TuiView.unlock);
      expect(tester.find(byType(UnlockForm)).single, same(form));
      expect(field().enabled, isFalse);
      expect(submittedDraft.text, isEmpty);
      expect(submittedDraft.canUndo, isFalse);
      expect(tester.renderToString(), isNot(contains('Opening Keybay')));
      expect(tester.renderToString(), isNot(contains('Unlocking…')));
      await Future<void>.delayed(
        tuiBusyDelay + const Duration(milliseconds: 20),
      );
      tester.pump();
      expect(tester.renderToString(), contains('Unlocking…'));
      expect(actionRow(), originalActionRow);
      tester.type('ignored-while-checking');
      tester.sendKey(const KeyEvent(KeyCode.enter));
      tester.pump();
      expect(field().controller!.text, isEmpty);
      gate.complete();
      await tester.settle();
      expect(tester.find(byType(UnlockForm)).single, same(form));
      expect(field().focusNode, same(focus));
      expect(focus.hasFocus, isTrue);
      expect(field().obscureText, isTrue);
      expect(field().validationError, contains('Check your passphrase'));
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        isEmpty,
      );
      expect(actionRow(), originalActionRow);
      expect(tester.renderToString(), isNot(contains('wrong')));
      expect(model.keys, isEmpty);
      final views = <TuiView>[];
      model.addListener(() => views.add(model.view));
      tester.type('good');
      await tester.settle();
      expect(field().validationError, isNull);
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(views, isNot(contains(TuiView.opening)));
      expect(model.unlockError, isNull);
      expect(model.showsBusy, isFalse);
      expect(tester.find(byType(UnlockForm)), isEmpty);
      expect(tester.renderToString(), contains('acme/a'));
      expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
    });
  }

  test('cancel during an unlock check closes a late session', () async {
    final session = await store.open();
    await session.auth.add(PassphraseCredential(phrase: bytes('good')));
    await session.close();
    await model.open();
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    tester.type('good');
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    store.gateNextOperation(gate.future);
    tester.sendKey(const KeyEvent(KeyCode.enter));
    tester.pump();
    expect(model.busy, isTrue);
    tester.sendKey(const KeyEvent(KeyCode.escape));
    tester.pump();
    expect(model.ending, isTrue);
    gate.complete();
    await model.close();
    await tester.settle();
    expect(model.hasSession, isFalse);
    expect(model.keys, isEmpty);
    expect(exits, 1);
    expect(tester.find(byType(UnlockForm)), isEmpty);
    expect(store.deriver.lastBorrowedInputIsCleared, isTrue);
  });

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'unlock offers a compact recovery link before reset at $size',
      () async {
        final session = await store.open();
        await session.auth.add(PassphraseCredential(phrase: bytes('good')));
        await session.close();
        await model.open();
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.type('discarded-draft');
        await tester.settle();
        final draft =
            (tester.find(byType(TextInput)).single.widget as TextInput)
                .controller!;
        expect(tester.renderToString(), isNot(contains('Reset')));
        final link = tester.semantics().single(
          role: SemanticRole.button,
          label: 'Forgot passphrase?',
        );
        final bounds = link.bounds!;
        expect(bounds.right - bounds.left, 'Forgot passphrase?'.length);
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.moved,
            button: MouseButton.none,
            col: bounds.left,
            row: bounds.top,
          ),
        );
        await tester.settle();
        final buffer = tester.render();
        expect(
          buffer.atColRow(bounds.left, bounds.top).style.underline,
          isTrue,
        );
        expect(
          buffer.atColRow(bounds.right, bounds.top).style.underline,
          isFalse,
        );
        expect(
          buffer.atColRow(bounds.left, bounds.top).style.foreground,
          isNot(const AnsiColor(9)),
        );
        for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
          tester.sendMouse(
            MouseEvent(
              kind: kind,
              button: MouseButton.left,
              col: bounds.right + 1,
              row: bounds.top,
            ),
          );
        }
        await tester.settle();
        expect(model.view, TuiView.unlock);
        await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Forgot passphrase?',
        );
        await tester.settle();
        expect(model.view, TuiView.recovery);
        expect(draft.text, isEmpty);
        expect(draft.canUndo, isFalse);
        expect(tester.find(byType(TextInput)), isEmpty);
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.button, label: 'Back')
              .focused,
          isTrue,
        );
        await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Reset Keybay…',
        );
        await tester.settle();
        expect(model.view, TuiView.reset);
        expect(tester.renderToString(), contains('Type RESET to confirm:'));
        expect(tester.renderToString(), contains("can't be undone"));
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.view, TuiView.recovery);
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.view, TuiView.unlock);
        final field = tester.find(byType(TextInput)).single.widget as TextInput;
        expect(field.controller!.text, isEmpty);
        expect(field.focusNode!.hasFocus, isTrue);
        expect(model.ending, isFalse);
      },
    );
  }

  test(
    'terminal authorization failure clears input before any SDK call',
    () async {
      await model.close();
      model.dispose();
      var opens = 0;
      model = createNativeTuiModel(
        openSession: ({credential}) {
          opens++;
          return store.open(credential: credential);
        },
        resetStore: store.reset,
        authorize: () {
          throw StateError('terminal lost');
        },
        onExit: () {},
      );
      final phrase = bytes('must-be-cleared');
      await model.open(phrase);
      expect(opens, 0);
      expect(phrase, everyElement(0));
      expect(model.status, isNot(contains('must-be-cleared')));
    },
  );

  test(
    'names only until explicit reveal; copy is exact and independent',
    () async {
      await model.open();
      expect(model.revealed, isFalse);
      await model.read(copy: true);
      expect(model.revealed, isFalse);
      expect(copied.single, 'first-secret\nnext line\r\n🔑\x1b[31m');
      await model.read();
      expect(model.revealed, isTrue);
      expect(safeTuiText(model.valueText), contains(r'\u{1b}[31m'));
      model.select('acme/z');
      expect(model.revealed, isFalse);
      await model.read();
      expect(model.valueText, 'second-secret');
      model.search('ACME/A');
      expect(model.selectedKey, 'acme/a');
      expect(model.revealed, isFalse);
    },
  );

  test('selection invalidates an outstanding read; close awaits it', () async {
    await model.open();
    final gate = Completer<void>();
    store.gateNextOperation(gate.future);
    final reading = model.read();
    expect(model.busy, isTrue);
    model.select('acme/z');
    await model.read(copy: true);
    expect(copied, isEmpty);
    gate.complete();
    await reading;
    expect(model.revealed, isFalse);
    final next = Completer<void>();
    store.gateNextOperation(next.future);
    final pending = model.read();
    final closing = model.close();
    expect(exits, 0);
    expect(model.view, TuiView.closing);
    next.complete();
    await pending;
    await closing;
    expect(exits, 1);
    expect(model.hasSession, isFalse);
  });

  test('dismissed edit never mounts its late plaintext', () async {
    await model.open();
    final gate = Completer<void>();
    store.gateNextOperation(gate.future);
    final reading = model.read(edit: true);
    model.navigate(TuiView.browse);
    gate.complete();
    await reading;
    expect(model.view, TuiView.browse);
    expect(model.revealed, isFalse);
  });

  test('new/edit/delete/clear retain the session and protection', () async {
    await model.open();
    model.navigate(TuiView.passphrase);
    final phrase = bytes('secret-passphrase');
    await model.changePassphrase(phrase);
    expect(phrase, everyElement(0));
    expect(model.protected, isTrue);
    final value = bytes('line one\nline two');
    model.navigate(TuiView.create);
    await model.save('acme/new', value, replace: false);
    expect(value, everyElement(0));
    expect(model.selectedKey, 'acme/new');
    await model.read(edit: true);
    expect(model.takeEditText(), 'line one\nline two');
    await model.save('acme/new', bytes('replacement'), replace: true);
    model.navigate(TuiView.delete);
    await model.deleteSelected();
    expect(model.keys, isNot(contains('acme/new')));
    model.navigate(TuiView.clear);
    await model.clearRecords();
    expect(model.keys, isEmpty);
    expect(model.protected, isTrue);
    expect(model.hasSession, isTrue);
    model.navigate(TuiView.removePassphrase);
    await model.removePassphrase();
    expect(model.protected, isFalse);
  });

  test('simple and namespaced names remain distinct through CRUD', () async {
    await model.open();
    for (final key in ['x', 'x/y']) {
      model.navigate(TuiView.create);
      await model.save(key, bytes('value for $key'), replace: false);
      expect(model.selectedKey, key);
      await model.read(edit: true);
      expect(model.takeEditText(), 'value for $key');
      await model.save(key, bytes('edited $key'), replace: true);
    }
    for (final key in ['x', 'x/y']) {
      model.select(key);
      await model.read(copy: true);
      expect(copied.last, 'edited $key');
      model.navigate(TuiView.delete);
      await model.deleteSelected();
      expect(model.keys, isNot(contains(key)));
    }
  });

  test('stale session closes without offering record-context reset', () async {
    await model.open();
    final other = await store.open();
    await other.auth.add(PassphraseCredential(phrase: bytes('changed')));
    await other.close();
    await model.read();
    expect(model.view, TuiView.failed);
    expect(model.hasSession, isFalse);
    expect(model.resetFromFailure, isFalse);
  });

  test('typed reset exits without initializing a replacement store', () async {
    await model.open();
    model.navigate(TuiView.reset);
    await model.reset('yes');
    expect(model.hasSession, isTrue);
    await model.reset(resetConfirmation);
    await model.close();
    expect(exits, 1);
    expect(model.hasSession, isFalse);
    final fresh = await store.open();
    expect(fresh.wasInitialized, isTrue);
    await fresh.close();
  });

  test('binary/oversized values never reach Copy or display', () async {
    final session = await store.open();
    await session.setBytes('acme/a', Uint8List.fromList([0xff, 0]));
    await session.close();
    await model.open();
    await model.read(copy: true);
    expect(copied, isEmpty);
    expect(model.revealed, isFalse);
    expect(model.hasSession, isTrue);
    expect(
      () => decodeTuiValue(Uint8List(KeybayLimits.recordValueBytes + 1)),
      throwsFormatException,
    );
  });

  test(
    'dismissal cannot keep the TUI open after a submitted reset succeeds',
    () async {
      await model.close();
      model.dispose();
      final gate = Completer<void>();
      exits = 0;
      model = createNativeTuiModel(
        openSession: store.open,
        resetStore: () => gate.future,
        authorize: () {},
        onExit: () {
          exits++;
        },
      );
      await model.open();
      model.navigate(TuiView.reset);
      final resetting = model.reset(resetConfirmation);
      model.navigate(TuiView.unlock);
      gate.complete();
      await resetting;
      await Future<void>.delayed(Duration.zero);
      expect(model.ending, isTrue);
      expect(exits, 1);
    },
  );

  test('Copy failure is redacted and leaves session usable', () async {
    await model.close();
    model.dispose();
    model = createNativeTuiModel(
      openSession: store.open,
      resetStore: store.reset,
      authorize: () {},
      copyText: (_) async {
        throw const TuiCopyException();
      },
      onExit: () {},
    );
    await model.open();
    await model.read(copy: true);
    expect(model.hasSession, isTrue);
    expect(model.status, contains('could not be confirmed'));
    expect(model.revealed, isFalse);
  });

  test('widget search, reveal and Copy keep field clipboard empty', () async {
    final tester = FleuryTester(clipboard: DiscardClipboard());
    addTearDown(tester.dispose);
    await model.open();
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    expect(tester.renderToString(), contains('acme/a'));
    expect(tester.renderToString(), isNot(contains('first-secret')));
    tester.sendKey(KeyEvent(KeyCode.char(' ')));
    await tester.settle();
    expect(tester.renderToString(), contains('first-secret'));
    tester.sendKey(KeyEvent(KeyCode.char('c')));
    await tester.settle();
    expect(copied, hasLength(1));
    expect(tester.clipboard.readInProcess(), isNull);
    tester.sendKey(KeyEvent(KeyCode.char('/')));
    tester.type('z');
    await tester.settle();
    expect(model.query, 'z');
    expect(model.selectedKey, 'acme/z');
    tester.type('r');
    await tester.settle();
    expect(model.query, 'zr');
    expect(model.revealed, isFalse);
    expect(tester.renderToString(), contains('No matching keys'));
  });

  test(
    'search click, Down and row clicks restore shortcuts across focus changes',
    () async {
      final tester = FleuryTester(clipboard: DiscardClipboard());
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final initial = tester.renderToString(emptyMark: ' ').split('\n');
      final searchRow = initial.indexWhere(
        (line) => line.contains('Find a key…'),
      );
      final searchCol = initial[searchRow].indexOf('Find a key…');
      Future<void> click(int col, int row) async {
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: col,
            row: row,
          ),
        );
        await tester.settle();
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.up,
            button: MouseButton.left,
            col: col,
            row: row,
          ),
        );
        await tester.settle();
      }

      await click(searchCol, searchRow);
      final placeholder = tester
          .render()
          .atColRow(searchCol + 1, searchRow)
          .style;
      expect(placeholder.foreground, const RgbColor(0x90, 0x90, 0x90));
      expect(placeholder.dim, isFalse);
      expect(
        tester.render().atColRow(searchCol - 2, searchRow).style.foreground,
        const AnsiColor(6),
      );
      tester.type('z');
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(KeyEvent(KeyCode.char('c')));
      await tester.settle();
      expect(copied, ['second-secret']);
      expect(model.query, 'z');
      tester.sendKey(KeyEvent(KeyCode.char('/')));
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.end));
      tester.sendKey(const KeyEvent(KeyCode.backspace));
      tester.type('a');
      await tester.settle();
      expect(model.query, 'a');
      final rows = tester.renderToString(emptyMark: ' ').split('\n');
      final keyRow = rows.indexWhere((line) => line.contains('acme/a'));
      expect(keyRow, greaterThanOrEqualTo(0), reason: rows.join('\n'));
      await click(rows[keyRow].indexOf('acme/a'), keyRow);
      tester.sendKey(KeyEvent(KeyCode.char('c')));
      await tester.settle();
      expect(copied.last, startsWith('first-secret'));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(KeyEvent(KeyCode.char('c')));
      await tester.settle();
      expect(copied, hasLength(3));
      expect(copied.last, 'second-secret');
      await click(searchCol, searchRow);
      tester.sendKey(const KeyEvent(KeyCode.end));
      tester.type('c');
      await tester.settle();
      expect(model.query, 'ac');
      expect(copied, hasLength(3));
    },
  );

  test('revealed values share the masks right edge', () async {
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    await model.open();
    model.select('acme/a');
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    final hidden = tester.renderToString(emptyMark: ' ').split('\n');
    final masked = hidden.firstWhere((line) => line.contains('••••••••'));
    final rightEdge = masked.indexOf('••••••••') + 8;
    await model.read();
    await tester.settle();
    final rendered = tester.renderToString(emptyMark: ' ').split('\n');
    final first = rendered.singleWhere((line) => line.contains('first-secret'));
    final wrapped = rendered.singleWhere((line) => line.contains('next line'));
    expect(first.trimRight().length, rightEdge);
    expect(wrapped.trimRight().length, rightEdge);
    // It still begins after the name, never in the name's own column.
    expect(first.indexOf('first-secret'), greaterThan(first.indexOf('acme/a')));
  });

  test('display keeps ordinary text and escapes only unsafe runes', () {
    // Printable international text is readable; anything that could make the
    // display disagree with the stored bytes is rewritten.
    expect(safeTuiText('café 中文 🔑'), 'café 中文 🔑');
    expect(safeTuiText('a\nb'), 'a\nb');
    expect(safeTuiText('a\u202eb'), r'a\u{202e}b');
    expect(safeTuiText('a\u200db'), r'a\u{200d}b');
    expect(safeTuiText('a\u0007b'), r'a\u{7}b');
    expect(safeTuiText('a\rb'), r'a\u{d}b');
    expect(safeTuiText('\ufeff'), r'\u{feff}');
    expect(safeTuiText('a\\b'), r'a\\b');
    // Format characters, including a prepended concatenation mark that would
    // otherwise fold the next character into an unpainted cluster.
    expect(safeTuiText('g\u0600TAIL'), r'g\u{600}TAIL');
    expect(safeTuiText('a\u200cb'), r'a\u{200c}b');
    expect(safeTuiText('a\u00adb'), r'a\u{ad}b');
    expect(safeTuiText('\u3164'), r'\u{3164}');
    expect(safeTuiText('tag\u{e0041}'), r'tag\u{e0041}');
    // Text that would be drawn in zero cells is shown escaped; combining
    // accents and emoji selectors on a base keep rendering as themselves.
    expect(safeTuiText('\u0301a'), r'\u{301}a');
    expect(
      safeTuiText('a\n\u0301'),
      'a\n'
      r'\u{301}',
    );
    expect(safeTuiText('\ufe0f'), r'\u{fe0f}');
    expect(safeTuiText('e\u0301'), 'e\u0301');
    expect(safeTuiText('\u2764\ufe0f'), '\u2764\ufe0f');
    expect(needsTuiEscaping('\u0301x', allowNewlines: true), isTrue);
    expect(needsTuiEscaping('e\u0301', allowNewlines: true), isFalse);
    expect(needsTuiEscaping('g\u0600T', allowNewlines: true), isTrue);
    // Width is measured in cells, not code units, so a wide glyph cannot
    // overflow the column it was laid out in.
    expect(longestEscapedLine('中文'), 4);
    expect(longestEscapedLine('ab'), 2);
    expect(wrapEscapedLine('中文中', 4), ['中文', '中']);
  });

  test(
    'arrows move from the first result to search and back without reads',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      store.files.beforeOpen = () async =>
          fail('Navigation must not read storage');
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      expect(model.selectedKey, 'acme/z');
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      await tester.settle();
      expect(
        tester.semantics().single(label: 'Search key names').focused,
        isTrue,
      );
      tester.type('z');
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      await tester.settle();
      expect(
        tester.semantics().single(label: 'Search key names').focused,
        isFalse,
      );
      expect(model.selectedKey, 'acme/z');
      tester.sendKey(const KeyEvent(KeyCode.arrowUp));
      tester.sendKey(const KeyEvent(KeyCode.end));
      tester.type('q');
      await tester.settle();
      expect(model.query, 'zq');
      expect(model.ending, isFalse);
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      tester.sendKey(const KeyEvent(KeyCode.backspace));
      await tester.settle();
      expect(model.query, 'z');
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      await tester.settle();
      store.files.beforeOpen = null;
      tester.sendKey(KeyEvent(KeyCode.char('c')));
      await tester.settle();
      expect(copied, ['second-secret']);
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'hide preserves context and idle Escape dismisses feedback at $size',
      () async {
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        await model.open();
        model.search('acme');
        model.select('acme/z');
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.sendKey(KeyEvent(KeyCode.char(' ')));
        await tester.settle();
        expect(model.revealed, isTrue);
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.revealed, isFalse);
        expect(model.selectedKey, 'acme/z');
        expect(model.query, 'acme');
        tester.sendKey(KeyEvent(KeyCode.char(' ')));
        await tester.settle();
        final hide = tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Hide')
            .bounds!;
        for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
          tester.sendMouse(
            MouseEvent(
              kind: kind,
              button: MouseButton.left,
              col: hide.left,
              row: hide.top,
            ),
          );
          await tester.settle();
        }
        expect(model.revealed, isFalse);
        expect(model.selectedKey, 'acme/z');
        expect(model.query, 'acme');
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.query, isEmpty);
        expect(model.selectedKey, 'acme/z');
        model.message('A copy failure', failure: true);
        await tester.settle();
        expect(tester.renderToString(), contains('A copy failure'));
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(tester.renderToString(), isNot(contains('A copy failure')));
        expect(model.selectedKey, 'acme/z');
      },
    );

    test(
      'Edit save and cancel preserve the filter and selected key at $size',
      () async {
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        await model.open();
        model.search('z');
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        for (final save in [false, true]) {
          tester.sendKey(const KeyEvent(KeyCode.enter));
          await tester.settle();
          expect(model.view, TuiView.edit);
          tester.sendKey(
            save
                ? const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl})
                : const KeyEvent(KeyCode.escape),
          );
          await tester.settle();
          expect(model.view, TuiView.browse);
          expect(model.query, 'z');
          expect(model.selectedKey, 'acme/z');
          final search =
              tester.find(byType(TextInput)).single.widget as TextInput;
          expect(search.controller!.text, 'z');
          expect(tester.renderToString(), contains('› acme/z'));
        }
      },
    );

    test(
      'short vaults show records and hints follow actual focus at $size',
      () async {
        final session = await store.open();
        for (var i = 0; i < 35; i++) {
          await session.set(
            'service/${i.toString().padLeft(2, '0')}',
            'synthetic-value',
          );
        }
        await session.close();
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        await model.open();
        model.search('service/');
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        final initial = tester.renderToString(emptyMark: ' ');
        final visibleRows = initial
            .split('\n')
            .where((line) => line.contains('••••••••'))
            .length;
        expect(visibleRows, greaterThanOrEqualTo(size.cols == 80 ? 7 : 8));
        expect(tester.find(byType(Scrollbar)), isNotEmpty);
        for (final label in [
          'Copy',
          'Edit',
          'Delete',
          'New key',
          'Settings',
          'Quit',
        ]) {
          expect(initial, contains(label));
        }
        final row = initial
            .split('\n')
            .indexWhere((line) => line.contains('› service/00'));
        final col = initial.split('\n')[row].indexOf('› service/00');
        expect(tester.render().atColRow(col, row).style.bold, isTrue);
        tester.sendKey(KeyEvent(KeyCode.char('/')));
        await tester.settle();
        expect(tester.renderToString(), contains('Enter results · Esc clear'));
        expect(tester.renderToString(), isNot(contains('Enter edit')));
        expect(tester.render().atColRow(col, row).style.bold, isFalse);
        tester.sendKey(const KeyEvent(KeyCode.end));
        tester.type('missing');
        await tester.settle();
        expect(tester.renderToString(), contains('Esc clear'));
        expect(tester.renderToString(), isNot(contains('Enter results')));
        expect(tester.renderToString(), isNot(contains('Enter edit')));
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(tester.renderToString(), contains('Enter edit'));
        tester.sendKey(const KeyEvent(KeyCode.end));
        await tester.settle();
        expect(model.selectedKey, 'service/34');
        expect(tester.renderToString(), contains('› service/34'));
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(tester.renderToString(), contains('Alt+Enter new line'));
        final formRows = tester.renderToString().split('\n');
        expect(
          formRows.singleWhere((row) => row.contains('Alt+Enter new line')),
          contains('Value'),
        );
        expect(tester.renderToString(), isNot(contains('Enter save')));
        expectFormActions(tester);
        tester.sendKey(const KeyEvent(KeyCode.tab));
        await tester.settle();
        expect(tester.renderToString(), isNot(contains('Alt+Enter new line')));
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.selectedKey, 'service/34');
        expect(tester.renderToString(), contains('› service/34'));
      },
    );

    test('Settings hints follow the focused pane at $size', () async {
      final tester = FleuryTester(viewportSize: size);
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.settings);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      expect(tester.renderToString(), contains('→ actions'));
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      expect(tester.renderToString(), contains('← category'));
      expect(tester.renderToString(), isNot(contains('→ actions')));
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      expect(tester.renderToString(), contains('Back'));
      expect(tester.renderToString(), isNot(contains('← category')));
      expect(tester.renderToString(), isNot(contains('Tab cycles focus')));
    });
  }

  test('New clears only a filter that would hide the saved key', () async {
    await model.open();
    model.search('z');
    model.navigate(TuiView.create);
    await model.save('z-new', bytes('synthetic-value'), replace: false);
    expect(model.query, 'z');
    expect(model.selectedKey, 'z-new');
    model.navigate(TuiView.create);
    await model.save('another', bytes('synthetic-value'), replace: false);
    expect(model.query, isEmpty);
    expect(model.selectedKey, 'another');
  });

  test(
    'a revealed value uses spare row width, including the last column',
    () async {
      final session = await store.open();
      final records = {
        'openai/API_KEY':
            'v' * 58, // Fills the remaining content width exactly.
        'a' * 60: 'tiny', // A long name must not wrap beside a short value.
      };
      for (final entry in records.entries) {
        await session.set(entry.key, entry.value);
      }
      await session.close();
      final tester = FleuryTester(viewportSize: const CellSize(80, 24));
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      for (final entry in records.entries) {
        model.select(entry.key);
        await model.read();
        await tester.settle();
        final rows = tester.renderToString(emptyMark: ' ').split('\n');
        expect(
          rows.singleWhere((line) => line.contains(entry.key)),
          contains(entry.value),
        );
        final view = tester.find(byType(ValueView)).single.findRenderObject()!;
        expect(view.size.rows, 1);
      }
    },
  );

  for (final edit in [false, true]) {
    test(
      'Tab and Shift+Tab traverse every ${edit ? 'Edit' : 'New'} field and action',
      () async {
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        await model.open();
        if (edit) {
          model.select('acme/z');
          await model.read(edit: true);
        } else {
          model.navigate(TuiView.create);
        }
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        Future<void> tab({bool back = false}) async {
          tester.sendKey(
            KeyEvent(KeyCode.tab, modifiers: {if (back) KeyModifier.shift}),
          );
          await tester.settle();
        }

        if (!edit) await tab();
        expect(
          tester.semantics().single(label: 'Secret value').focused,
          isTrue,
        );
        await tab(back: true);
        if (edit) {
          expect(tester.find(byType(TextInput)), isEmpty);
          expect(tester.renderToString(), isNot(contains('read-only')));
          expect(tester.renderToString(), isNot(contains('Edit key')));
          expect(tester.renderToString(), contains('acme/z'));
          expect(
            tester
                .semantics()
                .single(label: 'Cancel', role: SemanticRole.button)
                .focused,
            isTrue,
          );
        } else {
          expect(tester.semantics().single(label: 'Key name').focused, isTrue);
          tester.type('tab-created');
        }
        await tab();
        expect(
          tester.semantics().single(label: 'Secret value').focused,
          isTrue,
        );
        final area = tester.find(byType(TextArea)).single.widget as TextArea;
        final draft = area.controller!.text;
        for (final label in [
          'Save',
          'Reveal',
          'Cancel',
          if (!edit) 'Key name',
          'Secret value',
        ]) {
          await tab();
          expect(
            tester
                .semantics()
                .single(
                  label: label,
                  role: ['Save', 'Cancel', 'Reveal'].contains(label)
                      ? SemanticRole.button
                      : null,
                )
                .focused,
            isTrue,
            reason: 'Expected focus on $label',
          );
        }
        expect(area.controller!.text, draft); // Tab never enters secret text.
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.view, TuiView.browse);
        expect(area.controller!.text, isEmpty);
      },
    );
  }

  for (final size in [const CellSize(40, 24), const CellSize(180, 50)]) {
    for (final view in [
      TuiView.delete,
      TuiView.clear,
      TuiView.removePassphrase,
    ]) {
      test('$view is a compact keyboard confirmation at $size', () async {
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        final longName = 'namespace/${'k' * 110}';
        if (view == TuiView.delete) {
          final session = await store.open();
          await session.set(longName, 'value');
          await session.delete('acme/a');
          await session.close();
        }
        await model.open();
        if (view == TuiView.delete) model.select(longName);
        model.navigate(view);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        final panel = tester.find(byType(Container)).single.findRenderObject()!;
        expect(panel.size.cols, lessThanOrEqualTo(60));
        expect(panel.size.rows, lessThanOrEqualTo(14));
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.button, label: 'Cancel')
              .focused,
          isTrue,
        );
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        final destination = switch (view) {
          TuiView.delete => TuiView.browse,
          TuiView.clear => TuiView.data,
          _ => TuiView.security,
        };
        expect(model.view, destination);
        expect(model.keys, hasLength(2));
        model.navigate(view);
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.view, destination);
      });
    }
  }

  test('delete requires moving focus from Cancel before Enter', () async {
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    await model.open();
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    tester.sendKey(KeyEvent(KeyCode.char('d')));
    await tester.settle();
    tester.sendKey(const KeyEvent(KeyCode.arrowRight));
    await tester.settle();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'Delete key')
          .focused,
      isTrue,
    );
    tester.sendKey(const KeyEvent(KeyCode.enter));
    await tester.settle();
    expect(model.view, TuiView.browse);
    expect(model.keys, ['acme/z']);
    expect(model.status, 'Deleted!');
    tester.sendKey(KeyEvent(KeyCode.char('c')));
    await tester.settle();
    expect(copied, ['second-secret']);
  });

  test('an empty vault focuses New key and restores it after cancel', () async {
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    await model.open();
    model.navigate(TuiView.clear);
    await model.clearRecords();
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'New key')
          .focused,
      isTrue,
    );
    tester.sendKey(const KeyEvent(KeyCode.enter));
    await tester.settle();
    expect(model.view, TuiView.create);
    tester.sendKey(const KeyEvent(KeyCode.escape));
    await tester.settle();
    expect(
      tester
          .semantics()
          .single(role: SemanticRole.button, label: 'New key')
          .focused,
      isTrue,
    );
    tester.sendKey(KeyEvent(KeyCode.char('q')));
    await tester.settle();
    expect(model.ending, isTrue);
  });

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    for (final protected in [false, true]) {
      test(
        'settings sidebar and content fit at $size, protected=$protected',
        () async {
          final tester = FleuryTester(viewportSize: size);
          addTearDown(tester.dispose);
          await model.open();
          if (protected) {
            model.navigate(TuiView.passphrase);
            await model.changePassphrase(bytes('disposable'));
          }
          model.navigate(TuiView.settings);
          tester.pumpWidget(KeybayTui(model: model));
          await tester.settle();
          expect(
            tester
                .semantics()
                .single(role: SemanticRole.button, label: 'Security')
                .focused,
            isTrue,
          );
          for (final category in ['Security', 'Data']) {
            final actionLabels = category == 'Security'
                ? [
                    protected ? 'Change passphrase' : 'Add passphrase',
                    if (protected) 'Remove passphrase',
                  ]
                : ['Clear all records', 'Reset Keybay'];
            final menu = tester.semantics().single(
              role: SemanticRole.button,
              label: category,
            );
            final first = tester.semantics().single(
              role: SemanticRole.button,
              label: actionLabels.first,
            );
            expect(menu.selected, isTrue);
            expect(first.bounds!.left, greaterThan(menu.bounds!.right));
            tester.sendKey(const KeyEvent(KeyCode.arrowRight));
            await tester.settle();
            for (final label in actionLabels) {
              final action = tester.semantics().single(
                role: SemanticRole.button,
                label: label,
              );
              expect(action.focused, isTrue);
              expect(action.bounds!.bottom, lessThanOrEqualTo(size.rows - 6));
              if (label != actionLabels.last) {
                tester.sendKey(const KeyEvent(KeyCode.arrowDown));
                await tester.settle();
              }
            }
            tester.sendKey(const KeyEvent(KeyCode.tab));
            await tester.settle();
            expect(
              tester
                  .semantics()
                  .single(role: SemanticRole.button, label: 'Back')
                  .focused,
              isTrue,
            );
            tester.sendKey(
              const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
            );
            await tester.settle();
            expect(
              tester
                  .semantics()
                  .single(role: SemanticRole.button, label: actionLabels.last)
                  .focused,
              isTrue,
            );
            tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
            await tester.settle();
            expect(
              tester
                  .semantics()
                  .single(role: SemanticRole.button, label: category)
                  .focused,
              isTrue,
            );
            if (category == 'Security') {
              tester.sendKey(const KeyEvent(KeyCode.arrowDown));
              await tester.settle();
            }
          }
          expect(model.protected, protected);
          tester.sendKey(const KeyEvent(KeyCode.escape));
          await tester.settle();
          expect(model.view, TuiView.browse);
        },
      );
    }
  }

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'settings distinguish current rows from keyboard focus at $size',
      () async {
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        await model.open();
        model.navigate(TuiView.settings);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();

        void expectFocus(String focusedLabel) {
          final semantics = tester.semantics();
          final cells = tester.render();
          for (final label in ['Security', 'Data', 'Add passphrase', 'Back']) {
            final node = semantics.single(
              role: SemanticRole.button,
              label: label,
            );
            expect(node.focused, label == focusedLabel, reason: '$label focus');
            if (label == 'Back') continue;
            final cell = cells.atColRow(node.bounds!.left, node.bounds!.top);
            expect(
              cell.style.background != null,
              label == focusedLabel,
              reason: 'only the focused row gets a filled highlight',
            );
            expect(
              cell.grapheme,
              label == 'Security' || label == 'Add passphrase' ? '›' : ' ',
            );
          }
          expect(
            semantics
                .single(role: SemanticRole.button, label: 'Security')
                .selected,
            isTrue,
          );
        }

        Future<void> press(KeyEvent key, String focusedLabel) async {
          tester.sendKey(key);
          await tester.settle();
          expectFocus(focusedLabel);
        }

        expectFocus('Security');
        await press(const KeyEvent(KeyCode.arrowRight), 'Add passphrase');
        await press(const KeyEvent(KeyCode.tab), 'Back');
        await press(
          const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
          'Add passphrase',
        );
        await press(const KeyEvent(KeyCode.arrowLeft), 'Security');
        await press(const KeyEvent(KeyCode.tab), 'Add passphrase');
        await press(
          const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
          'Security',
        );

        final target = tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Add passphrase')
            .bounds!;
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.moved,
            button: MouseButton.none,
            col: target.left,
            row: target.top,
          ),
        );
        await tester.settle();
        expectFocus('Security');
        // Press takes focus before release invokes the action.
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.down,
            button: MouseButton.left,
            col: target.left,
            row: target.top,
          ),
        );
        await tester.settle();
        expectFocus('Add passphrase');
        expect(model.view, TuiView.settings);
      },
    );
  }

  for (final policy in {
    null: 'Off',
    const Duration(minutes: 1): '1 minute',
  }.entries) {
    test('settings reports the host idle policy: ${policy.value}', () async {
      await model.close();
      model.dispose();
      model = createNativeTuiModel(
        openSession: store.open,
        resetStore: store.reset,
        authorize: () {},
        onExit: () {},
        idleTimeout: policy.key,
      );
      await model.open();
      model.navigate(TuiView.settings);
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      expect(tester.renderToString(), contains('Idle exit: ${policy.value}'));
    });
  }

  test(
    'settings selection changes content without invoking its actions',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.settings);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      expect(tester.renderToString(), contains('Passphrase: Off'));
      expect(tester.renderToString(), contains('Idle exit: 5 minutes'));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      await tester.settle();
      expect(model.view, TuiView.data);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Data')
            .focused,
        isTrue,
      );
      expect(tester.renderToString(), contains('Clear all records'));
      for (final label in ['Clear all records', 'Reset Keybay']) {
        final bounds = tester
            .semantics()
            .single(role: SemanticRole.button, label: label)
            .bounds!;
        expect(
          tester.render().atColRow(bounds.left, bounds.top).style.foreground,
          isNot(keybayTheme.errorStyle.foreground),
          reason: 'settings navigation stays neutral before confirmation',
        );
      }
      expect(tester.renderToString(), isNot(contains('Add passphrase')));
      expect(model.keys, hasLength(2));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Clear all records')
            .focused,
        isTrue,
      );
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.clear);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Cancel')
            .focused,
        isTrue,
      );
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      expect(model.view, TuiView.data);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Data')
            .selected,
        isTrue,
      );
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Clear all records')
            .focused,
        isTrue,
      );
    },
  );

  for (final protected in [false, true]) {
    test(
      'settings actions preserve confirmations, protected=$protected',
      () async {
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        await model.open();
        if (protected) {
          model.navigate(TuiView.passphrase);
          await model.changePassphrase(bytes('disposable'));
        }
        tester.pumpWidget(KeybayTui(model: model));
        for (final entry in {
          KeyCode.p: (TuiView.security, TuiView.passphrase),
          KeyCode.c: (TuiView.data, TuiView.clear),
          KeyCode.r: (TuiView.data, TuiView.reset),
          if (protected)
            KeyCode.x: (TuiView.security, TuiView.removePassphrase),
        }.entries) {
          model.navigate(entry.value.$1);
          await tester.settle();
          tester.sendKey(KeyEvent(entry.key));
          await tester.settle();
          expect(model.view, entry.value.$2);
          if (model.view == TuiView.clear ||
              model.view == TuiView.removePassphrase) {
            expect(
              tester
                  .semantics()
                  .single(role: SemanticRole.button, label: 'Cancel')
                  .focused,
              isTrue,
            );
          }
          expect(model.keys, ['acme/a', 'acme/z']);
          expect(model.protected, protected);
          tester.sendKey(const KeyEvent(KeyCode.escape));
          await tester.settle();
          expect(model.view, entry.value.$1);
        }
        model.navigate(TuiView.settings);
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.r));
        await tester.settle();
        expect(model.view, TuiView.settings);
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.view, TuiView.browse);
      },
    );
  }

  test(
    'settings sidebar and action rows accept clicks across their width',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.settings);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      Future<void> click(String label) async {
        final bounds = tester
            .semantics()
            .single(role: SemanticRole.button, label: label)
            .bounds!;
        for (final kind in [MouseEventKind.down, MouseEventKind.up]) {
          tester.sendMouse(
            MouseEvent(
              kind: kind,
              button: MouseButton.left,
              col: bounds.right - 1,
              row: bounds.top,
            ),
          );
          await tester.settle();
        }
      }

      await click('Data');
      expect(model.view, TuiView.data);
      expect(model.keys, hasLength(2));
      await click('Clear all records');
      expect(model.view, TuiView.clear);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Cancel')
            .focused,
        isTrue,
      );
    },
  );

  test('the resize screen has a working focused Quit action', () async {
    final tester = FleuryTester(viewportSize: const CellSize(30, 12));
    addTearDown(tester.dispose);
    await model.open();
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    expect(tester.renderToString(), contains('Resize'));
    tester.sendKey(const KeyEvent(KeyCode.enter));
    await tester.settle();
    expect(model.ending, isTrue);
  });

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test('every view keeps its actions visible at $size', () async {
      final tester = FleuryTester(viewportSize: size);
      addTearDown(tester.dispose);
      final longKey = 'a' * 120;
      final session = await store.open();
      await session.set(longKey, 'disposable\n\x1b[31m');
      await session.close();
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      // Opening needs a real pending operation; the slow-startup tests cover
      // its delayed Quit action at both minimum sizes.
      for (final view in TuiView.values.where(
        (v) => v != TuiView.closing && v != TuiView.opening,
      )) {
        model.navigate(TuiView.browse);
        if (view == TuiView.edit) {
          model.select(longKey);
          await model.read(edit: true);
        } else {
          model.navigate(view);
        }
        await tester.settle();
        void checkActions() {
          final actions = tester.semantics().where(role: SemanticRole.button);
          expect(actions, isNotEmpty, reason: '$view');
          for (final action in actions) {
            final bounds = action.bounds;
            expect(bounds, isNotNull, reason: '$view: ${action.label}');
            expect(
              bounds!.bottom - bounds.top,
              greaterThan(0),
              reason: '$view: ${action.label}',
            );
            expect(
              bounds.bottom,
              // Bottom padding plus the compact one-row busy indicator.
              lessThanOrEqualTo(size.rows - 2),
              reason:
                  '$view: ${action.label}\n${tester.renderToString(emptyMark: ' ')}',
            );
          }
        }

        checkActions();
        if (view == TuiView.edit) {
          expect(tester.find(byType(TextInput)), isEmpty);
          final keyLines = tester.renderToString(emptyMark: ' ').split('\n');
          expect(
            keyLines
                .map((line) => line.trim())
                .where((line) => RegExp(r'^a+$').hasMatch(line))
                .join(),
            longKey,
          );
          await tester.invokeSemanticAction(
            SemanticAction.activate,
            role: SemanticRole.button,
            label: 'Reveal',
          );
          await tester.settle();
          checkActions();
        }
      }
    });
  }

  test(
    'Reveal toggles the built-in field without exposing clipboard or semantic values',
    () async {
      final tester = FleuryTester(clipboard: DiscardClipboard());
      addTearDown(tester.dispose);
      await model.open();
      model.select('acme/z');
      await model.read(edit: true);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Reveal',
      );
      await tester.settle();
      final area = tester.find(byType(TextArea)).single.widget as TextArea;
      expect(area.obscureText, isFalse);
      expect(area.clipboardPolicy, TextClipboardPolicy.redacted);
      final screen = tester.renderToString();
      expect(screen, contains('second-secret'));
      expect(screen, isNot(contains('••••')));
      // Activating a framework button focuses it; editor-only guidance hides.
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Hide')
            .focused,
        isTrue,
      );
      expect(screen, isNot(contains('Alt+Enter new line')));
      expect(screen, isNot(contains('Tab focus')));
      expect(tester.find(byType(ValueView)), isEmpty);
      expect(
        tester.semantics().single(role: SemanticRole.textArea).value,
        isNull,
      );
      area.controller!.selection = TextSelection(
        baseOffset: 0,
        extentOffset: area.controller!.text.length,
      );
      await tester.settle();
      await tester.invokeSemanticAction(
        SemanticAction.copy,
        role: SemanticRole.textArea,
        label: 'Secret value',
      );
      expect(tester.clipboard.readInProcess(), isNull);
      await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.textArea,
        label: 'Secret value',
      );
      tester.sendKey(const KeyEvent(KeyCode.end));
      tester.type('-edited');
      await tester.settle();
      expect(area.controller!.text, 'second-secret-edited');
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Hide',
      );
      await tester.settle();
      expect(tester.renderToString(), isNot(contains('second-secret')));
    },
  );

  test(
    'form Ctrl+S and Ctrl+R preserve typing, focus and secret policy',
    () async {
      final tester = FleuryTester(clipboard: DiscardClipboard());
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.create);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.type('sr-key');
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(tester.semantics().single(label: 'Key name').focused, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      tester.type('sr-secret');
      await tester.settle();
      final field =
          (tester.find(byType(TextArea)).single.widget as TextArea).controller!;
      expect(field.text, 'sr-secret');
      expect(tester.renderToString(), contains('sr-secret'));
      expect(tester.renderToString(), contains('Value · revealed'));
      expect(tester.semantics().single(label: 'Secret value').value, isNull);
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(tester.renderToString(), isNot(contains('sr-secret')));
      expect(tester.semantics().single(label: 'Secret value').focused, isTrue);
      tester.sendKey(
        const KeyEvent(
          KeyCode.r,
          modifiers: {KeyModifier.ctrl},
          type: KeyEventType.repeat,
        ),
      );
      tester.sendKey(
        const KeyEvent(
          KeyCode.s,
          modifiers: {KeyModifier.ctrl},
          type: KeyEventType.repeat,
        ),
      );
      await tester.settle();
      expect(model.view, TuiView.create);
      expect(tester.renderToString(), isNot(contains('sr-secret')));
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(model.selectedKey, 'sr-key');
      expect(field.text, isEmpty);
      expect(field.canUndo, isFalse);
      expect(tester.clipboard.readInProcess(), isNull);
      await model.read(copy: true);
      expect(copied.single, 'sr-secret');
    },
  );

  test(
    'Ctrl+R round trips an escaped edit and Ctrl+S works from an action',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      await model.read(edit: true);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final field =
          (tester.find(byType(TextArea)).single.widget as TextArea).controller!;
      final original = field.text;
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(tester.find(byType(ValueView)), hasLength(1));
      expect(tester.renderToString(), contains(r'\u{1b}'));
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(tester.find(byType(TextArea)), hasLength(1));
      expect(tester.renderToString(), isNot(contains('first-secret')));
      expect(tester.semantics().single(label: 'Secret value').focused, isTrue);
      tester.sendKey(
        const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
      );
      await tester.settle();
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Cancel')
            .focused,
        isTrue,
      );
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(field.text, isEmpty);
      await model.read(copy: true);
      expect(copied.single, original);
    },
  );

  test(
    'passphrase paste preserves exact bytes through setup and unlock',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      const phrase = 'pass\tword\r\n🔑\x1b[31m';
      await model.open();
      model.navigate(TuiView.passphrase);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.paste(phrase);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      tester.paste(phrase);
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(tester.find(byType(ValueView)), hasLength(2));
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.protected, isTrue);
      await model.close();
      tester.pumpWidget(const SizedBox());
      model.dispose();
      model = createNativeTuiModel(
        openSession: store.open,
        resetStore: store.reset,
        authorize: () {},
        onExit: () {},
      );
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      expect(model.view, TuiView.unlock);
      tester.paste(phrase);
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(model.keys, ['acme/a', 'acme/z']);
      expect(tester.renderToString(), isNot(contains('pass')));
      // The SDK must accept the original, not a normalized approximation.
      await model.close();
      final session = await store.open(
        credential: PassphraseCredential(phrase: bytes(phrase)),
      );
      await session.close();
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'passphrase reveal covers both fields and conceals together at $size',
      () async {
        final tester = FleuryTester(
          clipboard: DiscardClipboard(),
          viewportSize: size,
        );
        addTearDown(tester.dispose);
        await model.open();
        model.navigate(TuiView.passphrase);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.type('first-draft');
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        tester.type('second-draft');
        await tester.settle();
        TextInput input(String label) => tester
            .find(byType(TextInput))
            .map((e) => e.widget as TextInput)
            .singleWhere((input) => input.semanticLabel == label);
        final first = input('Passphrase').controller!;
        final second = input('Confirm passphrase').controller!;

        void expectVisibility(bool shown) {
          final screen = tester.renderToString();
          for (final label in ['Passphrase', 'Confirm passphrase']) {
            final field = input(label);
            expect(field.obscureText, !shown);
            expect(field.clipboardPolicy, TextClipboardPolicy.redacted);
            expect(
              tester
                  .semantics()
                  .single(role: SemanticRole.textField, label: label)
                  .value,
              isNull,
            );
            expect(screen.contains(field.controller!.text), shown);
          }
        }

        await tester.invokeSemanticAction(
          SemanticAction.activate,
          role: SemanticRole.button,
          label: 'Reveal',
        );
        await tester.settle();
        expectVisibility(true);
        expect(
          tester.renderToString(),
          contains('Confirm passphrase · revealed'),
        );
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        expectVisibility(false);
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        model.conceal();
        await tester.settle();
        expectVisibility(false);

        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        tester.sendKey(
          const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        expectVisibility(false);
        expect(tester.renderToString(), contains("Passphrases don't match."));
        expect(first.text, 'first-draft');
        expect(second.text, 'second-draft');

        // Unsafe pasted text conceals both fields and is only revealed escaped.
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        second.selection = TextSelection(
          baseOffset: 0,
          extentOffset: second.text.length,
        );
        const controls = 'confirm\u202e\t';
        tester.paste(controls);
        await tester.settle();
        expect(second.text, controls);
        expectVisibility(false);
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        expect(tester.find(byType(ValueView)), hasLength(1));
        expect(tester.renderToString(), contains('first-draft'));
        expect(tester.renderToString(), contains(r'confirm\u{202e}'));
        expect(tester.renderToString(), isNot(contains('\u202e')));
        expect(
          tester.semantics().debugTree(includeState: true),
          isNot(contains('first-draft')),
        );
        expect(
          tester.semantics().debugTree(includeState: true),
          isNot(contains(r'confirm\u{202e}')),
        );
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        expect(input('Confirm passphrase').controller, same(second));
        expectVisibility(false);
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(first.text, isEmpty);
        expect(second.text, isEmpty);
        expect(first.canUndo, isFalse);
        expect(second.canUndo, isFalse);
        expect(tester.clipboard.readInProcess(), isNull);
      },
    );
  }

  test(
    'passphrase shortcuts retain confirmation and reset has no save chord',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.passphrase);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.type('sr-passphrase');
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.protected, isFalse);
      expect(tester.renderToString(), contains('Confirm your passphrase.'));
      tester.type('sr-passphrase');
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Confirm passphrase')
            .focused,
        isTrue,
      );
      final inputs = tester
          .find(byType(TextInput))
          .map((e) => e.widget as TextInput)
          .toList();
      expect(
        inputs
            .singleWhere((input) => input.semanticLabel == 'Passphrase')
            .obscureText,
        isFalse,
      );
      expect(
        inputs
            .singleWhere((input) => input.semanticLabel == 'Confirm passphrase')
            .obscureText,
        isFalse,
      );
      expect(
        inputs.every(
          (input) => input.clipboardPolicy == TextClipboardPolicy.redacted,
        ),
        isTrue,
      );
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.protected, isTrue);
      model.navigate(TuiView.reset);
      await tester.settle();
      tester.type(resetConfirmation);
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.view, TuiView.reset);
      expect(model.keys, hasLength(2));
      expect(tester.renderToString(), isNot(contains('Ctrl+S')));
    },
  );

  test(
    'form and confirmation colors distinguish focus, disclosure and danger',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.select('acme/z');
      await model.read(edit: true);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      CellStyle styleAt(String text) {
        final rows = tester.renderToString(emptyMark: ' ').split('\n');
        final row = rows.indexWhere((line) => line.contains(text));
        expect(row, greaterThanOrEqualTo(0));
        return tester.render().atColRow(rows[row].indexOf(text), row).style;
      }

      expect(styleAt('[Ctrl+S] Save').foreground, const AnsiColor(2));
      expect(styleAt('[Ctrl+R] Reveal').foreground, const AnsiColor(3));
      expect(styleAt('[Ctrl+S]').bold, isTrue);
      expect(styleAt('Save').bold, isFalse);
      expect(styleAt('acme/z').bold, isTrue);
      expect(tester.renderToString(), isNot(contains('Edit key')));
      expect(tester.renderToString(), isNot(contains('read-only')));
      final area = tester.semantics().single(label: 'Secret value').bounds!;
      CellStyle borderAt(CellRect bounds) =>
          tester.render().atColRow(bounds.left, bounds.top - 1).style;
      expect(borderAt(area).foreground, const AnsiColor(6));
      expect(tester.find(byType(TextInput)), isEmpty);
      expect(styleAt('acme/z').foreground, isNot(const AnsiColor(6)));
      tester.sendKey(
        const KeyEvent(KeyCode.tab, modifiers: {KeyModifier.shift}),
      );
      await tester.settle();
      expect(styleAt('[Esc] Cancel').inverse, isTrue);
      final cancelRows = tester.renderToString(emptyMark: ' ').split('\n');
      final cancelRow = cancelRows.indexWhere(
        (row) => row.contains('[Esc] Cancel'),
      );
      final cancelCol = cancelRows[cancelRow].indexOf('[Esc]');
      for (var offset = 0; offset < '[Esc] Cancel'.length; offset++) {
        expect(
          tester.render().atColRow(cancelCol + offset, cancelRow).style.inverse,
          isTrue,
        );
      }
      expect(borderAt(area).dim, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(styleAt('second-secret').foreground, const AnsiColor(3));
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.d));
      await tester.settle();
      expect(styleAt('Delete this key?').foreground, const AnsiColor(9));
      expect(styleAt('Delete key').foreground, const AnsiColor(9));
      expect(styleAt('Cancel').inverse, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      expect(styleAt('Delete key').inverse, isTrue);
      expect(styleAt('Delete key').foreground, const AnsiColor(9));
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'reset confirmation drives eligibility and inline errors at $size',
      () async {
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        await model.open();
        model.navigate(TuiView.reset);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        bool canReset() => tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Reset Keybay')
            .enabled;
        expect(canReset(), isFalse);
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(model.ending, isFalse);
        expect(model.keys, hasLength(2));
        final field = tester.semantics().single(label: 'Reset confirmation');
        expect(field.focused, isTrue);
        expect(field.validationError, 'Type RESET to confirm.');
        expect(tester.renderToString(), contains('Type RESET to confirm.'));
        expect(
          tester.semantics().where(role: SemanticRole.notification),
          isEmpty,
        );
        tester.type(resetConfirmation);
        await tester.settle();
        expect(canReset(), isTrue);
        expect(
          tester
              .semantics()
              .single(label: 'Reset confirmation')
              .validationError,
          isNull,
        );
        tester.sendKey(const KeyEvent(KeyCode.backspace));
        await tester.settle();
        expect(canReset(), isFalse);
        tester.type('T');
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(model.ending, isTrue);
      },
    );
  }

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    for (final name in ['bad key', 'acme/z']) {
      test(
        'name rejection preserves a correctable masked draft: $name at $size',
        () async {
          final tester = FleuryTester(viewportSize: size);
          addTearDown(tester.dispose);
          await model.open();
          model.navigate(TuiView.create);
          tester.pumpWidget(KeybayTui(model: model));
          await tester.settle();
          tester.type(name);
          tester.sendKey(const KeyEvent(KeyCode.enter));
          await tester.settle();
          expect(
            tester.semantics().single(label: 'Key name').focused,
            isTrue,
            reason: 'Enter validates the name before asking for a value',
          );
          expect(
            tester.semantics().single(label: 'Key name').validationError,
            isNotNull,
          );
          tester.sendKey(const KeyEvent(KeyCode.tab));
          await tester.settle();
          tester.paste('exact-draft\nsecond-line');
          await tester.settle();
          final field =
              (tester.find(byType(TextArea)).single.widget as TextArea)
                  .controller!;
          final expected = field.text;
          tester.sendKey(
            const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
          );
          tester.sendKey(
            const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}),
          );
          await tester.settle();
          expect(model.view, TuiView.create);
          expect(model.keys, hasLength(2));
          expect(field.text, expected);
          expect(tester.semantics().single(label: 'Key name').focused, isTrue);
          expect(tester.renderToString(), isNot(contains('exact-draft')));
          final error = name == 'bad key'
              ? 'Use a name like'
              : 'That key exists';
          expect(
            tester.semantics().single(label: 'Key name').validationError,
            startsWith(error),
          );
          final rows = tester.renderToString(emptyMark: ' ').split('\n');
          final errorRow = rows.indexWhere((line) => line.contains(error));
          expect(errorRow, greaterThan(0));
          expect(
            errorRow,
            lessThan(rows.indexWhere((line) => line.trim() == 'Value')),
          );
          expectFormActions(tester);
          tester.sendKey(const KeyEvent(KeyCode.home));
          tester.sendKey(
            const KeyEvent(KeyCode.end, modifiers: {KeyModifier.shift}),
          );
          tester.type('corrected');
          tester.sendKey(
            const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}),
          );
          await tester.settle();
          expect(model.view, TuiView.browse);
          expect(model.selectedKey, 'corrected');
          expect(field.text, isEmpty);
          expect(field.canUndo, isFalse);
          await model.read(copy: true);
          expect(copied.single, expected);
        },
      );
    }
  }

  for (final empty in [false, true]) {
    test(
      'zero-result Escape restores actions with empty vault=$empty',
      () async {
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        await model.open();
        if (empty) {
          model.navigate(TuiView.clear);
          await model.clearRecords();
        }
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.char('/')));
        tester.type('no-matching-key');
        await tester.settle();
        expect(
          tester.renderToString(),
          contains(empty ? 'No keys yet' : 'No matching keys'),
        );
        tester.sendKey(const KeyEvent(KeyCode.escape));
        await tester.settle();
        expect(model.query, isEmpty);
        expect(
          tester.semantics().single(label: 'Search key names').focused,
          isFalse,
        );
        if (empty) {
          expect(
            tester
                .semantics()
                .single(role: SemanticRole.button, label: 'New key')
                .focused,
            isTrue,
          );
          final status = model.status;
          for (final key in [KeyCode.c, KeyCode.e, KeyCode.d]) {
            tester.sendKey(KeyEvent(key));
            await tester.settle();
            expect(model.view, TuiView.browse);
            expect(model.status, status);
          }
        } else {
          tester.sendKey(const KeyEvent(KeyCode.c));
          await tester.settle();
          expect(copied, hasLength(1));
        }
        tester.sendKey(const KeyEvent(KeyCode.q));
        await tester.settle();
        expect(model.ending, isTrue);
      },
    );
  }

  test('form Cancel returns to its origin; unlock Cancel exits', () async {
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    await model.open();
    tester.pumpWidget(KeybayTui(model: model));
    for (final origin in [TuiView.security, TuiView.firstUse]) {
      model.navigate(origin);
      await tester.settle();
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Add passphrase',
      );
      await tester.settle();
      tester.type('cancelled-secret');
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      expect(model.view, origin);
      expect(tester.renderToString(), isNot(contains('cancelled-secret')));
    }
    for (final origin in [TuiView.data, TuiView.recovery]) {
      model.navigate(origin);
      await tester.settle();
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: origin == TuiView.recovery ? 'Reset Keybay…' : 'Reset Keybay',
      );
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      expect(model.view, origin);
    }
    model.navigate(TuiView.unlock);
    await tester.settle();
    await tester.invokeSemanticAction(
      SemanticAction.activate,
      role: SemanticRole.button,
      label: 'Cancel',
    );
    await tester.settle();
    expect(model.ending, isTrue);
  });

  for (final view in [
    TuiView.create,
    TuiView.edit,
    TuiView.passphrase,
    TuiView.unlock,
  ]) {
    test(
      '$view conceals and retains its draft across blur and undersized resize',
      () async {
        final tester = FleuryTester(clipboard: DiscardClipboard());
        addTearDown(tester.dispose);
        if (view == TuiView.unlock) {
          final session = await store.open();
          await session.auth.add(
            PassphraseCredential(phrase: bytes('disposable')),
          );
          await session.close();
        }
        await model.open();
        if (view == TuiView.edit) {
          await model.read(
            edit: true,
          ); // Includes escaped control and Unicode text.
        } else if (view != TuiView.unlock) {
          model.navigate(view);
        }
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        if (view == TuiView.create) {
          tester.type('retained');
          tester.sendKey(const KeyEvent(KeyCode.tab));
          await tester.settle();
        }
        if (view != TuiView.edit) tester.type('draft-material');
        await tester.settle();
        TextEditingController controller() =>
            view == TuiView.create || view == TuiView.edit
            ? (tester.find(byType(TextArea)).single.widget as TextArea)
                  .controller!
            : tester
                  .find(byType(TextInput))
                  .map((e) => e.widget as TextInput)
                  .singleWhere((input) => input.semanticLabel == 'Passphrase')
                  .controller!;
        final field = controller();
        final original = field.text;
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        model.conceal();
        await tester.settle();
        expect(controller(), same(field));
        expect(field.text, original);
        expect(
          tester.renderToString(),
          isNot(
            contains(view == TuiView.edit ? 'first-secret' : 'draft-material'),
          ),
        );
        expect(tester.find(byType(ValueView)), isEmpty);
        tester.viewportSize = const CellSize(30, 12);
        model.conceal();
        await tester.settle();
        expect(tester.renderToString(), contains('Draft kept hidden.'));
        expect(tester.find(byType(TextArea)), isEmpty);
        expect(tester.find(byType(TextInput)), isEmpty);
        expect(field.text, original);
        tester.viewportSize = const CellSize(80, 20);
        model.conceal();
        await tester.settle();
        expect(controller(), same(field));
        expect(field.text, original);
        expect(
          tester.renderToString(),
          isNot(
            contains(view == TuiView.edit ? 'first-secret' : 'draft-material'),
          ),
        );
        expect(tester.clipboard.readInProcess(), isNull);
        await model.close();
        await tester.settle();
        expect(field.text, isEmpty);
        expect(field.canUndo, isFalse);
      },
    );
  }

  test(
    'busy shortcuts stay disabled and conceal does not cancel an accepted save',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final readGate = Completer<void>();
      addTearDown(() {
        if (!readGate.isCompleted) readGate.complete();
      });
      store.gateNextOperation(readGate.future);
      final reading = model.read();
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      await tester.settle();
      for (final action in tester.semantics().where(
        role: SemanticRole.button,
      )) {
        expect(
          action.focused,
          isFalse,
          reason: 'Right during reveal loading stays on the selected key',
        );
      }
      for (final key in [
        KeyCode.n,
        KeyCode.s,
        KeyCode.d,
        KeyCode.e,
        KeyCode.r,
        KeyCode.c,
      ]) {
        tester.sendKey(KeyEvent(key));
        await tester.settle();
        expect(model.view, TuiView.browse);
        expect(model.busy, isTrue);
      }
      model.conceal();
      readGate.complete();
      await reading;
      expect(model.revealed, isFalse);
      model.navigate(TuiView.create);
      await tester.settle();
      tester.type('committed');
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      tester.type('accepted-draft');
      final field =
          (tester.find(byType(TextArea)).single.widget as TextArea).controller!;
      final writeGate = Completer<void>();
      addTearDown(() {
        if (!writeGate.isCompleted) writeGate.complete();
      });
      store.gateNextOperation(writeGate.future);
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(model.busy, isTrue);
      expect(field.text, isEmpty);
      model.conceal();
      writeGate.complete();
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(model.selectedKey, 'committed');
      await model.read(copy: true);
      expect(copied.single, 'accepted-draft');
    },
  );

  test(
    'an accepted large paste remains complete across an immediate resize',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.create);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.type('pasted');
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      final pasted = 'x' * KeybayLimits.recordValueBytes;
      tester.paste(pasted);
      tester.viewportSize = const CellSize(30, 12);
      model.conceal();
      await tester.settle();
      tester.viewportSize = const CellSize(80, 20);
      await tester.settle();
      final area = tester.find(byType(TextArea)).single.widget as TextArea;
      expect(area.controller!.text.length, pasted.length);
      expect(area.controller!.text == pasted, isTrue);
      expect(area.obscureText, isTrue);
      expect(tester.renderToString(), isNot(contains('xxxxx')));
    },
  );

  test(
    'control-text paste into a shown field conceals without losing the paste',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.create);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Reveal',
      );
      await tester.invokeSemanticAction(
        SemanticAction.focus,
        role: SemanticRole.textArea,
        label: 'Secret value',
      );
      final text = '\u202e${'x' * 100000}';
      tester.paste(text);
      await tester.settle();
      final area = tester.find(byType(TextArea)).single.widget as TextArea;
      expect(area.controller!.text, text);
      expect(area.obscureText, isTrue);
      expect(tester.renderToString(), isNot(contains('\u202e')));
      expect(tester.find(byType(ValueView)), isEmpty);
    },
  );

  test(
    'masked multiline form preserves text and disposes Undo on cancel',
    () async {
      final tester = FleuryTester(clipboard: DiscardClipboard());
      addTearDown(tester.dispose);
      await model.open();
      await model.read(edit: true);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      expect(tester.renderToString(), isNot(contains('first-secret')));
      expect(
        tester.semantics().debugTree(includeState: true),
        isNot(contains('first-secret')),
      );
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      model.navigate(TuiView.create);
      await tester.settle();
      final area = tester.find(byType(TextArea)).single.widget as TextArea;
      expect(area.controller!.text, isEmpty);
      area.controller!.undo();
      expect(area.controller!.text, isEmpty);
    },
  );

  for (final size in [
    const CellSize(40, 24),
    const CellSize(80, 24),
    const CellSize(180, 50),
  ]) {
    test(
      'new key form supports Key → Enter → Value → Enter at $size',
      () async {
        final tester = FleuryTester(
          viewportSize: size,
          clipboard: DiscardClipboard(),
        );
        addTearDown(tester.dispose);
        await model.open();
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.sendKey(KeyEvent(KeyCode.char('n')));
        await tester.settle();
        final screen = tester.renderToString(emptyMark: ' ');
        expect(screen, contains('Key'));
        expect(screen, contains('Value'));
        expectFormActions(tester);
        expect(
          screen.split('\n').indexWhere((row) => row.contains('[Ctrl+S] Save')),
          lessThan(18),
        );
        tester.type('test2');
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        tester.type('never-show-this');
        await tester.settle();
        final field = (tester.find(byType(TextArea)).single.widget as TextArea)
            .controller!;
        expect(field.text, 'never-show-this');
        expect(tester.renderToString(), isNot(contains('never-show-this')));
        expect(
          tester.semantics().single(role: SemanticRole.textArea).value,
          isNull,
        );
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        expect(model.view, TuiView.browse);
        expect(model.selectedKey, 'test2');
        expect(model.status, 'Saved!');
        expect(field.text, isEmpty);
        expect(field.canUndo, isFalse);
        await model.read(copy: true);
        expect(copied.single, 'never-show-this');
      },
    );
  }

  test(
    'Alt+Enter and multiline paste edit the value without submitting',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.create);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.type('multiline');
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      tester.type('first');
      tester.sendKey(
        const KeyEvent(KeyCode.enter, modifiers: {KeyModifier.alt}),
      );
      tester.type('second');
      tester.paste('\nthird\nfourth');
      await tester.settle();
      expect(model.view, TuiView.create);
      expect(model.keys, isNot(contains('multiline')));
      expectFormActions(tester);
      expect(tester.renderToString(), isNot(contains('third')));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.browse);
      await model.read(copy: true);
      expect(copied.single, 'first\nsecond\nthird\nfourth');
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test('notifications fit without taking focus at $size', () async {
      final tester = FleuryTester(viewportSize: size);
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final focused = tester.focusManager.focusedNode;
      model.message('Copied!');
      await tester.settle();
      expect(tester.focusManager.focusedNode, same(focused));
      model.message(
        'Could not copy. Check clipboard access and try again.',
        failure: true,
      );
      await tester.settle();
      final screen = tester.renderToString(emptyMark: ' ');
      // The toast wraps within the viewport and never steals focus.
      expect(screen, contains('Could not copy.'));
      expect(screen, isNot(contains('ErrorWidget')));
      for (final line in screen.split('\n')) {
        expect(line.length, lessThanOrEqualTo(size.cols));
      }
      expect(tester.focusManager.focusedNode, same(focused));
      tester.sendKey(const KeyEvent(KeyCode.e));
      await tester.settle();
      expect(model.view, TuiView.edit);
    });
  }

  test(
    'copy feedback persists through a retry and unrelated success',
    () async {
      await model.close();
      model.dispose();
      var failCopy = true;
      final delivery = Completer<void>();
      addTearDown(() {
        if (!delivery.isCompleted) delivery.complete();
      });
      model = createNativeTuiModel(
        openSession: store.open,
        resetStore: store.reset,
        authorize: () {},
        copyText: (_) async {
          if (failCopy) throw const TuiCopyException();
          await delivery.future;
        },
        onExit: () {},
      );
      await model.open();
      final tester = FleuryTester(viewportSize: const CellSize(40, 24));
      addTearDown(tester.dispose);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      await model.read(copy: true);
      await tester.settle();
      String feedback() => tester
          .semantics()
          .where(role: SemanticRole.notification)
          .singleWhere((node) => node.state.severity != null)
          .label!;
      expect(feedback(), contains('Copy could not be confirmed'));
      final failureText = feedback();
      tester.pump(const Duration(minutes: 2));
      expect(feedback(), failureText);
      model.message('Unrelated success');
      await tester.settle();
      expect(feedback(), failureText);
      failCopy = false;
      final retry = model.read(copy: true);
      await tester.settle();
      expect(feedback(), failureText);
      model.message('Closing soon without input.', scope: TuiView.closing);
      await tester.settle();
      expect(feedback(), failureText);
      delivery.complete();
      await retry;
      await tester.settle();
      expect(feedback(), 'Copied!');
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        hasLength(1),
      );
      tester.pump(tuiNoticeDuration);
      expect(
        tester.semantics().where(role: SemanticRole.notification),
        isEmpty,
      );
    },
  );

  test('cleared and dismissed messages never replay after a rebuild', () async {
    await model.open();
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    model.message('Stale result', failure: true);
    model.navigate(TuiView.create);
    await tester.settle();
    expect(tester.semantics().where(role: SemanticRole.notification), isEmpty);
    model.navigate(TuiView.browse);
    model.message('Persistent failure', failure: true);
    await tester.settle();
    tester.sendKey(const KeyEvent(KeyCode.escape));
    await tester.settle();
    expect(tester.semantics().where(role: SemanticRole.notification), isEmpty);
    model.hide();
    await tester.settle();
    expect(tester.semantics().where(role: SemanticRole.notification), isEmpty);
    model.message('Next result');
    await tester.settle();
    expect(
      tester.semantics().single(role: SemanticRole.notification).label,
      'Next result',
    );
  });

  test(
    'Copy confirms only after delivery, expires, and never expires an error',
    () async {
      await model.close();
      model.dispose();
      final delivery = Completer<void>();
      model = createNativeTuiModel(
        openSession: store.open,
        resetStore: store.reset,
        authorize: () {},
        copyText: (_) => delivery.future,
        onExit: () {},
      );
      await model.open();
      final copying = model.read(copy: true);
      expect(model.status, isNot('Copied!'));
      delivery.complete();
      await copying;
      expect(model.status, 'Copied!');
      expect(model.error, isFalse);
      expect(model.revealed, isFalse);
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      // The toast carries the confirmation; the model no longer times it out.
      final lines = tester.renderToString(emptyMark: ' ').split('\n');
      final row = lines.indexWhere((line) => line.contains('Copied!'));
      expect(row, greaterThanOrEqualTo(15));
      // The toast's clock is the scheduler's, so advance it rather than
      // waiting on wall time.
      tester.pump(tuiNoticeDuration + const Duration(milliseconds: 200));
      expect(tester.renderToString(), isNot(contains('Copied!')));
      // A newer error is never cleared by an older confirmation.
      model.message('A later failure', failure: true);
      await tester.settle();
      expect(tester.renderToString(), contains('A later failure'));
      expect(model.status, 'A later failure');
      expect(model.error, isTrue);
    },
  );

  test(
    'editor save preserves untouched bytes and releases its field controller',
    () async {
      final tester = FleuryTester(clipboard: DiscardClipboard());
      addTearDown(tester.dispose);
      await model.open();
      await model.read(edit: true);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final field =
          (tester.find(byType(TextArea)).single.widget as TextArea).controller!;
      final original = field.text;
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Reveal',
      );
      await tester.settle();
      expect(tester.renderToString(), contains('first-secret'));
      expect(tester.find(byType(TextArea)), isEmpty);
      expect(tester.find(byType(ValueView)), hasLength(1));
      expect(tester.renderToString(), isNot(contains('••••')));
      expect(tester.renderToString(), contains(r'\u{1b}'));
      await tester.invokeSemanticAction(
        SemanticAction.activate,
        role: SemanticRole.button,
        label: 'Save',
      );
      await tester.settle();
      expect(field.text, isEmpty);
      expect(field.canUndo, isFalse);
      expect(model.view, TuiView.browse);
      expect(model.revealed, isFalse);
      await model.read(copy: true);
      expect(copied.single, original);
    },
  );

  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    test(
      'passphrase mismatch retains masked fields and can be corrected at $size',
      () async {
        final tester = FleuryTester(viewportSize: size);
        addTearDown(tester.dispose);
        await model.open();
        model.navigate(TuiView.passphrase);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        tester.type('first-draft');
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        tester.type('other-draft');
        final fields = tester
            .find(byType(TextInput))
            .map((e) => e.widget as TextInput);
        final inputs = [
          for (final label in ['Passphrase', 'Confirm passphrase'])
            fields
                .singleWhere((field) => field.semanticLabel == label)
                .controller!,
        ];
        tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        tester.sendKey(
          const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        expect(inputs[0].text, 'first-draft');
        expect(inputs[1].text, 'other-draft');
        expect(model.protected, isFalse);
        expect(model.status, isEmpty);
        expect(tester.renderToString(), contains("Passphrases don't match."));
        expect(tester.renderToString(), isNot(contains('first-draft')));
        expect(tester.renderToString(), isNot(contains('other-draft')));
        final confirm = tester.semantics().single(
          role: SemanticRole.textField,
          label: 'Confirm passphrase',
        );
        expect(confirm.focused, isTrue);
        expect(confirm.validationError, "Passphrases don't match.");
        expect(
          tester
              .render()
              .atColRow(confirm.bounds!.left, confirm.bounds!.top - 1)
              .style
              .foreground,
          const AnsiColor(9),
        );
        for (final label in ['Save', 'Reveal', 'Cancel']) {
          final action = tester.semantics().single(
            role: SemanticRole.button,
            label: label,
          );
          expect(action.bounds!.bottom, lessThanOrEqualTo(size.rows - 2));
        }
        // Edit the existing confirmation and let normal input clear validation.
        inputs[1].selection = TextSelection(
          baseOffset: 0,
          extentOffset: inputs[1].text.length,
        );
        tester.type('first-draft');
        await tester.settle();
        expect(
          tester.renderToString(),
          isNot(contains("Passphrases don't match.")),
        );
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.textField, label: 'Confirm passphrase')
              .validationError,
          isNull,
        );
        expect(
          tester
              .render()
              .atColRow(confirm.bounds!.left, confirm.bounds!.top - 1)
              .style
              .foreground,
          const AnsiColor(6),
        );
        tester.sendKey(
          const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}),
        );
        await tester.settle();
        expect(model.protected, isTrue);
        expect(model.view, TuiView.security);
        expect(tester.renderToString(), contains('Passphrase: On'));
        for (final input in inputs) {
          expect(input.text, isEmpty);
          expect(input.canUndo, isFalse);
        }
        // The corrected draft protects the actual disposable SDK store.
        await model.close();
        await expectLater(store.open(), throwsA(isA<KeybayException>()));
        final reopened = await store.open(
          credential: PassphraseCredential(phrase: bytes('first-draft')),
        );
        expect(await reopened.listKeys(), ['acme/a', 'acme/z']);
        await reopened.close();
      },
    );
  }

  test(
    'empty passphrases get field feedback; cancelled mismatch clears both drafts',
    () async {
      final tester = FleuryTester(viewportSize: const CellSize(80, 20));
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.passphrase);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.s, modifiers: {KeyModifier.ctrl}));
      await tester.settle();
      expect(tester.renderToString(), contains('Enter a passphrase.'));
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.textField, label: 'Passphrase')
            .focused,
        isTrue,
      );
      tester.type('kept-until-cancel');
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      tester.type('different');
      await tester.settle();
      final confirmation = tester
          .find(byType(TextInput))
          .map((e) => e.widget as TextInput)
          .singleWhere((field) => field.semanticLabel == 'Confirm passphrase');
      expect(confirmation.controller!.text, 'different');
      expect(confirmation.focusNode!.hasFocus, isTrue);
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(tester.renderToString(), contains("Passphrases don't match."));
      final inputs = tester
          .find(byType(TextInput))
          .map((e) => (e.widget as TextInput).controller!)
          .toList();
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      for (final input in inputs) {
        expect(input.text, isEmpty);
        expect(input.canUndo, isFalse);
      }
      expect(model.protected, isFalse);
      expect(
        tester.renderToString(),
        isNot(contains("Passphrases don't match.")),
      );
    },
  );

  test(
    'out-of-bound secret paste discards the editor without storing a prefix',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.passphrase);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.paste('x' * 20000);
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(model.protected, isFalse);
      expect(tester.find(byType(TextArea)), isEmpty);
      expect(model.status, contains('draft was discarded'));
    },
  );

  test(
    'oversized record paste erases the immediate edit and its undo history',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      model.navigate(TuiView.create);
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.type('too-large');
      tester.sendKey(const KeyEvent(KeyCode.tab));
      await tester.settle();
      final area = tester.find(byType(TextArea)).single.widget as TextArea;
      final draft = area.controller!;
      tester.paste('x' * (KeybayLimits.recordValueBytes + 1));
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(model.keys, isNot(contains('too-large')));
      expect(draft.text, isEmpty);
      expect(draft.canUndo, isFalse);
      expect(tester.find(byType(TextArea)), isEmpty);
      expect(model.status, contains('draft was discarded'));
    },
  );

  for (final view in [TuiView.browse, TuiView.create, TuiView.reset]) {
    test(
      'invalid text preserves accepted input and selection in $view',
      () async {
        final tester = FleuryTester();
        addTearDown(tester.dispose);
        await model.open();
        model.navigate(view);
        tester.pumpWidget(KeybayTui(model: model));
        await tester.settle();
        if (view == TuiView.browse) {
          tester.type('/');
          await tester.settle();
        }
        tester.type(view == TuiView.reset ? 'RES' : 'acme');
        await tester.settle();
        final input = tester.find(byType(TextInput)).single.widget as TextInput;
        final controller = input.controller!;
        controller.selection = const TextSelection(
          baseOffset: 3,
          extentOffset: 1,
        );
        final accepted = controller.value;
        final query = model.query;
        tester.paste('bad🔑');
        await tester.settle();
        expect(controller.value, accepted);
        tester.paste('x' * 1000000);
        await tester.settle();
        expect(controller.value, accepted);
        expect(model.query, query);
        tester.type('ok');
        await tester.settle();
        expect(controller.text, view == TuiView.reset ? 'Rok' : 'aoke');
        expect(
          tester
              .semantics()
              .single(role: SemanticRole.textField, label: input.semanticLabel)
              .validationError,
          isNull,
        );
        controller.undo();
        await tester.settle();
        expect(controller.value, accepted);
        expect(model.ending, isFalse);
      },
    );
  }

  test('terminal controls in plain fields are rejected before paint', () async {
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    await model.open();
    model.navigate(TuiView.create);
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    tester.paste('bad\x1b[31mname');
    await tester.settle();
    final name =
        (tester.find(byType(TextInput)).single.widget as TextInput).controller!;
    expect(name.text, isEmpty);
    expect(tester.renderToString(), isNot(contains('\x1b')));
  });

  test('outgoing views cannot reopen or read into a new editor', () async {
    await model.close();
    model.dispose();
    var opens = 0;
    model = createNativeTuiModel(
      openSession: ({credential}) {
        opens++;
        return store.open(credential: credential);
      },
      resetStore: store.reset,
      authorize: () {},
      copyText: (text) async {
        copied.add(text);
      },
      onExit: () {},
    );
    await model.open();
    final phrase = bytes('discarded');
    await model.open(phrase);
    expect(opens, 1);
    expect(phrase, everyElement(0));
    await model.read(edit: true);
    await model.read(copy: true);
    expect(copied, isEmpty);
    expect(model.takeEditText(), contains('first-secret'));
    model.navigate(TuiView.browse);
    final value = bytes('stale callback');
    await model.save('acme/new', value, replace: false);
    expect(value, everyElement(0));
    expect(model.keys, isNot(contains('acme/new')));
  });

  test(
    'Space toggles visibility, Enter edits, and r no longer reveals',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      expect(tester.renderToString(), isNot(contains('platform protection')));
      tester.sendKey(const KeyEvent(KeyCode.r));
      await tester.settle();
      expect(model.revealed, isFalse);
      tester.sendKey(KeyEvent(KeyCode.char(' ')));
      await tester.settle();
      expect(model.revealed, isTrue);
      tester.sendKey(KeyEvent(KeyCode.char(' ')));
      await tester.settle();
      expect(model.revealed, isFalse);
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.edit);
      expect(
        (tester.find(byType(TextArea)).single.widget as TextArea).obscureText,
        isTrue,
      );
      expect(tester.renderToString(), isNot(contains('first-secret')));
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      tester.sendKey(KeyEvent(KeyCode.char(' ')));
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.edit);
      expect(
        (tester.find(byType(TextArea)).single.widget as TextArea).obscureText,
        isTrue,
      );
    },
  );

  test(
    'Space remains text in search; Enter selects a result before editing',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.sendKey(KeyEvent(KeyCode.char('/')));
      tester.type('acme');
      tester.sendBatch(
        InputBatch(key: KeyEvent(KeyCode.char(' ')), committedText: ' '),
      );
      await tester.settle();
      expect(model.query, 'acme ');
      expect(model.revealed, isFalse);
      tester.sendKey(const KeyEvent(KeyCode.backspace));
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.browse);
      expect(model.revealed, isFalse);
      tester.sendKey(const KeyEvent(KeyCode.enter));
      await tester.settle();
      expect(model.view, TuiView.edit);
    },
  );

  test(
    'search handoff accepts an immediate reveal before rebuilding',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.sendKey(KeyEvent(KeyCode.char('/')));
      tester.type('z');
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.enter));
      tester.sendKey(KeyEvent(KeyCode.char(' ')));
      await tester.settle();
      expect(model.query, 'z');
      expect(model.selectedKey, 'acme/z');
      expect(model.revealed, isTrue);
      expect(model.valueText, 'second-secret');
    },
  );

  test(
    'buttons show hover without moving focus or activating, disabled buttons do not',
    () async {
      final tester = FleuryTester();
      addTearDown(tester.dispose);
      var activated = 0;
      tester.pumpWidget(
        Row(
          children: [
            TuiAction(label: 'Save', onPressed: () => activated++),
            const SizedBox(width: 2),
            const TuiAction(label: 'Disabled', onPressed: null),
          ],
        ),
      );
      await tester.settle();
      Future<void> hover(String label) async {
        final node = tester.semantics().single(
          role: SemanticRole.button,
          label: label,
        );
        tester.sendMouse(
          MouseEvent(
            kind: MouseEventKind.moved,
            button: MouseButton.none,
            col: node.bounds!.left,
            row: node.bounds!.top,
          ),
        );
        await tester.settle();
      }

      bool underlined(String label) {
        final node = tester.semantics().single(
          role: SemanticRole.button,
          label: label,
        );
        return tester
            .render()
            .atColRow(node.bounds!.left, node.bounds!.top)
            .style
            .underline;
      }

      await hover('Save');
      expect(underlined('Save'), isTrue);
      expect(
        tester
            .semantics()
            .single(role: SemanticRole.button, label: 'Save')
            .focused,
        isFalse,
      );
      expect(activated, 0);
      await hover('Disabled');
      expect(underlined('Save'), isFalse);
      expect(underlined('Disabled'), isFalse);
      expect(activated, 0);
    },
  );

  test('finder selection and action focus never read masked values', () async {
    final tester = FleuryTester();
    addTearDown(tester.dispose);
    await model.open();
    store.files.beforeOpen = () async => fail('Browsing must not read storage');
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();
    tester.sendKey(const KeyEvent(KeyCode.arrowDown));
    await tester.settle();
    expect(model.selectedKey, 'acme/z');
    tester.sendKey(const KeyEvent(KeyCode.tab));
    await tester.settle();
    final screen = tester.renderToString(emptyMark: ' ');
    expect(screen, contains('› acme/z'));
    expect(model.revealed, isFalse);
    expect(tester.find(byType(ValueView)), isEmpty);
    expect(
      tester.semantics().debugTree(includeState: true),
      isNot(contains('second-secret')),
    );
    store.files.beforeOpen = null;
  });

  test(
    'revealed row scrolls its full value and Escape returns to names',
    () async {
      final session = await store.open();
      await session.set(
        'acme/a',
        List.generate(30, (i) => 'line-$i').join('\n'),
      );
      await session.close();
      final tester = FleuryTester(viewportSize: const CellSize(40, 24));
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      tester.sendKey(KeyEvent(KeyCode.char(' ')));
      await tester.settle();
      expect(tester.renderToString(), contains('line-0'));
      expect(tester.renderToString(), isNot(contains('line-29')));
      expect(tester.renderToString(), contains('[d] Delete'));
      final rows = tester.renderToString().split('\n');
      for (final line in ['line-0', 'line-1']) {
        final row = rows.indexWhere((row) => row.contains(line));
        final col = rows[row].indexOf(line);
        expect(
          tester.render().atColRow(col, row).style.foreground,
          keybayColors.warning,
          reason: 'value lines share disclosure styling without a row cursor',
        );
      }
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      tester.sendKey(const KeyEvent(KeyCode.end));
      await tester.settle();
      expect(model.selectedKey, 'acme/a');
      expect(tester.renderToString(), contains('line-29'));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      await tester.settle();
      expect(model.selectedKey, 'acme/a'); // Value edge contains navigation.
      tester.sendKey(const KeyEvent(KeyCode.arrowLeft));
      await tester.settle();
      expect(model.revealed, isTrue);
      expect(tester.renderToString(), contains('→ value'));
      expect(tester.renderToString(), contains('line-29'));
      tester.sendKey(const KeyEvent(KeyCode.arrowRight));
      await tester.settle();
      expect(tester.renderToString(), contains('← keys'));
      expect(tester.renderToString(), contains('line-29'));
      tester.sendKey(const KeyEvent(KeyCode.escape));
      await tester.settle();
      expect(tester.find(byType(ValueView)), isEmpty);
      expect(tester.renderToString(), isNot(contains('line-29')));
      tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      await tester.settle();
      expect(model.selectedKey, 'acme/z');
      expect(model.revealed, isFalse);
    },
  );

  test(
    'narrow value wrapping preserves characters at the scroll edge',
    () async {
      final tester = FleuryTester(viewportSize: const CellSize(12, 1));
      addTearDown(tester.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      tester.pumpWidget(
        ValueView(text: '0123456789ABCDE', maxRows: 1, focusNode: focus),
      );
      await tester.settle();
      expect(tester.renderToString(), contains('0123456789A'));
      focus.requestFocus();
      await tester.settle();
      tester.sendKey(const KeyEvent(KeyCode.end));
      await tester.settle();
      expect(tester.renderToString(), contains('BCDE'));
    },
  );

  for (final size in [
    const CellSize(40, 24),
    const CellSize(80, 20),
    const CellSize(80, 24),
    const CellSize(120, 32),
  ]) {
    test('browse renders with bounded layout at $size', () async {
      final tester = FleuryTester(viewportSize: size);
      addTearDown(tester.dispose);
      await model.open();
      tester.pumpWidget(KeybayTui(model: model));
      await tester.settle();
      final screen = tester.renderToString(emptyMark: ' ');
      expect(screen, contains('acme/a'));
      expect(screen, isNot(contains('Values hidden')));
      expect(screen, isNot(contains('Value revealed')));
      expect(screen, isNot(contains('Error')));
      expect(screen, isNot(contains('first-secret')));
      final keyRows = screen.split('\n').where((row) => row.contains('acme/'));
      expect(keyRows, hasLength(2));
      expect(keyRows.every((row) => row.endsWith('••••••••')), isTrue);
      expect(
        keyRows.map((row) => row.indexOf('••••••••')).toSet(),
        hasLength(1),
      );
      for (final action in [
        '[Space] Reveal',
        '[c] Copy',
        '[e] Edit',
        '[d] Delete',
        '[n] New key',
        '[s] Settings',
        '[q] Quit',
      ]) {
        expect(screen, contains(action));
      }
      const labels = [
        'Reveal',
        'Copy',
        'Edit',
        'Delete',
        'New key',
        'Settings',
        'Quit',
      ];
      final before = [
        for (final label in labels)
          tester
              .semantics()
              .single(role: SemanticRole.button, label: label)
              .bounds!,
      ];
      final columns = size.cols < 80 ? 2 : 4;
      for (var i = 0; i < before.length; i++) {
        expect(before[i].left, before[i % columns].left);
        expect(before[i].top, before.first.top + i ~/ columns);
        expect(before[i].bottom - before[i].top, 1);
        if (i % columns != 0) {
          expect(before[i].left, greaterThan(before[i - 1].right));
        }
      }
      await model.read();
      await tester.settle();
      for (var i = 0; i < labels.length; i++) {
        final after = tester
            .semantics()
            .single(
              role: SemanticRole.button,
              label: i == 0 ? 'Hide' : labels[i],
            )
            .bounds!;
        expect(after.left, before[i].left);
        expect(after.top, before[i].top);
      }
    });
  }
}
