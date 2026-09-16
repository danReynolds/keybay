// Disposable observations for the Fleury dogfood review. No SDK or clipboard.
// Run from Keybay: dart run doc/reviews/fixtures/fleury_keybay_probe.dart
// This standalone review fixture uses the CLI's existing workspace dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';

Future<void> main() async {
  final results = <String, Object>{};
  final rich = FleuryTester(viewportSize: const CellSize(30, 5));
  rich.pumpWidget(
    const RichText(
      text: TextSpan(text: 'New key', style: CellStyle(inverse: true)),
    ),
  );
  await rich.settle();
  final cells = rich.render();
  results['richTextInverse'] = [
    for (var x = 0; x < 7; x++) cells.atColRow(x, 0).style.inverse,
  ];
  rich.dispose();

  final menu = FleuryTester(viewportSize: const CellSize(30, 5));
  final activations = <int>[];
  menu.pumpWidget(
    ListView.separated(
      autofocus: true,
      itemCount: 2,
      itemBuilder: (_, i, _) => Text('Action $i'),
      separatorBuilder: (_, _) => const Text('----------'),
      onSelect: activations.add,
    ),
  );
  await menu.settle();
  final rows = menu.renderToString(emptyMark: ' ').split('\n');
  final dividerRow = rows.indexWhere((line) => line.contains('----------'));
  if (dividerRow < 0) throw StateError('Divider was not rendered');
  menu.sendMouse(
    MouseEvent(
      kind: MouseEventKind.down,
      button: MouseButton.left,
      col: 2,
      row: dividerRow,
    ),
  );
  await menu.settle();
  results['dividerClickActivations'] = activations;
  menu.dispose();

  final editor = FleuryTester(viewportSize: const CellSize(30, 5));
  final controller = TextEditingController();
  editor.pumpWidget(TextArea(controller: controller, autofocus: true));
  await editor.settle();
  final input = 'x' * (256 * 1024);
  editor.paste(input);
  final beforeUnmount = controller.text.length;
  editor.pumpWidget(const Text('Temporarily hidden'));
  await editor.settle();
  results['pasteThenUnmount'] = {
    'received': input.length,
    'beforeUnmount': beforeUnmount,
    'retained': controller.text.length,
  };
  editor.dispose();
  controller.dispose();

  final decorated = FleuryTester(viewportSize: const CellSize(30, 5));
  const inputField = TextInput(semanticLabel: 'Draft', autofocus: true);
  decorated.pumpWidget(const Container(color: AnsiColor(2), child: inputField));
  await decorated.settle();
  decorated.type('synthetic draft');
  await decorated.settle();
  final draftBefore = decorated.semantics().single(label: 'Draft').value;
  decorated.pumpWidget(const Container(child: inputField));
  await decorated.settle();
  results['containerColorThenNull'] = {
    'before': draftBefore,
    'after': decorated.semantics().single(label: 'Draft').value,
  };
  decorated.dispose();

  print(const JsonEncoder.withIndent('  ').convert(results));
}
