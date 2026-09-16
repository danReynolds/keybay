// Received-paste/unmount comparison using synthetic text only.
// Run from Keybay: dart run doc/reviews/fixtures/paste_policy_probe.dart
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';

Future<void> main() async {
  final results = <String, Object>{};
  for (final entry in <String, TextPastePolicy>{
    'default': const TextPastePolicy(),
    'previousKeybay': const TextPastePolicy(
      largePasteThreshold: 1024 * 1024,
      chunkSize: 1024 * 1024 + 1,
    ),
    'immediate': const TextPastePolicy.immediate(),
  }.entries) {
    final tester = FleuryTester(viewportSize: const CellSize(30, 5));
    final controller = TextEditingController(preserveText: true);
    tester.pumpWidget(
      TextArea(
        controller: controller,
        autofocus: true,
        pastePolicy: entry.value,
      ),
    );
    await tester.settle();
    final input = 'x' * (256 * 1024);
    tester.paste(input);
    final atReturn = controller.text.length;
    tester.pumpWidget(const Text('Temporarily hidden'));
    await tester.settle();
    results[entry.key] = {
      'received': input.length,
      'committedWhenPasteReturns': atReturn,
      'retainedAfterUnmount': controller.text.length,
      'exact': controller.text == input,
    };
    tester.dispose();
    controller.dispose();
  }
  print(const JsonEncoder.withIndent('  ').convert(results));
}
