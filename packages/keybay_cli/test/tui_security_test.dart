@Tags(['unit'])
library;

import 'dart:convert';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/clipboard.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';
import 'package:keybay_cli/src/tui/store.dart';
import 'package:test/test.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

void main() {
  test('the shared TUI value limit matches the native SDK', () {
    expect(tuiRecordValueBytes, KeybayLimits.recordValueBytes);
  });

  for (final size in [
    const CellSize(40, 24),
    const CellSize(80, 20),
    const CellSize(120, 32),
  ]) {
    test(
      'secret previews stay out of every semantic surface at $size',
      () async {
        const sentinel = 's3cr3t';
        final store = V2TestKeybay();
        final session = await store.open();
        await session.set('probe/key', '$sentinel\n' * 30 + '\u202e\t');
        await session.close();
        final model = createNativeTuiModel(
          openSession: store.open,
          resetStore: store.reset,
          authorize: () {},
          onExit: () {},
        );
        final tester = FleuryTester(
          viewportSize: size,
          clipboard: DiscardClipboard(),
        );
        void expectRedacted() {
          final tree = tester.semantics();
          for (final node in tree.nodes) {
            expect(node.label, isNot(contains(sentinel)));
            expect(node.value?.toString(), isNot(contains(sentinel)));
          }
          expect(
            jsonEncode(tree.toInspectionJson()),
            isNot(contains(sentinel)),
          );
          expect(
            jsonEncode(tester.accessibilitySnapshot().toJson()),
            isNot(contains(sentinel)),
          );
          expect(tester.clipboard.readInProcess(), isNull);
        }

        void reveal() => tester.sendKey(
          const KeyEvent(KeyCode.r, modifiers: {KeyModifier.ctrl}),
        );
        try {
          await model.open();
          tester.pumpWidget(KeybayTui(model: model));
          await tester.settle();
          expectRedacted();
          await model.read();
          await tester.settle();
          expect(tester.renderToString(), contains(sentinel));
          expectRedacted();
          tester.sendKey(const KeyEvent(KeyCode.arrowRight));
          tester.sendKey(const KeyEvent(KeyCode.pageDown));
          await tester.settle();
          expectRedacted();
          await model.read(edit: true);
          await tester.settle();
          expectRedacted();
          reveal();
          await tester.settle();
          expect(tester.find(byType(ValueView)), isNotEmpty);
          expectRedacted();
          tester.sendKey(const KeyEvent(KeyCode.escape));
          await tester.settle();
          expectRedacted();

          model.navigate(TuiView.passphrase);
          await tester.settle();
          tester.type(sentinel);
          reveal();
          await tester.settle();
          expect(tester.renderToString(), contains(sentinel));
          expectRedacted();
          reveal();
          tester.paste('\u202e\t');
          reveal();
          await tester.settle();
          expect(tester.find(byType(ValueView)), isNotEmpty);
          expect(tester.renderToString(), contains(sentinel));
          expectRedacted();
          model.conceal();
          await tester.settle();
          expect(tester.renderToString(), isNot(contains(sentinel)));
          expectRedacted();
          tester.sendKey(const KeyEvent(KeyCode.escape));
          await tester.settle();
          expectRedacted();
        } finally {
          tester.dispose();
          await model.close();
          model.dispose();
          await store.dispose();
        }
      },
    );
  }
}
