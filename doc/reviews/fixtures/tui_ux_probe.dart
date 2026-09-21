// Reproducible UX observations, not acceptance tests for the observed defects.
// Only an in-memory test store, synthetic values, and a fake clipboard callback.
// Run from the repository root:
// dart --suppress-analytics run doc/reviews/fixtures/tui_ux_probe.dart
// Optional cell snapshots: append an output directory under build/.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:fleury_widgets/fleury_widgets.dart'
    show Form, FormController, FormField;
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';

import '../../../packages/keybay/test/support/v2_test_keybay.dart';

Future<void> main(List<String> arguments) async {
  final observations = <Object>[];
  final screens = <Object>[];
  for (final size in [const CellSize(40, 24), const CellSize(80, 20)]) {
    final store = V2TestKeybay();
    final seed = await store.open();
    for (var i = 0; i < 35; i++) {
      await seed.set('service/${i.toString().padLeft(2, '0')}', 'example-$i');
    }
    await seed.close();
    final model = createNativeTuiModel(
      openSession: store.open,
      resetStore: store.reset,
      authorize: () {},
      copyText: (_) async {},
      onExit: () {},
    );
    final tester = FleuryTester(viewportSize: size);
    await model.open();
    tester.pumpWidget(KeybayTui(model: model));
    await tester.settle();

    Future<void> key(KeyCode code, {bool ctrl = false}) async {
      tester.sendKey(KeyEvent(code, modifiers: {if (ctrl) KeyModifier.ctrl}));
      await tester.settle();
    }

    void observe(String scenario, Map<String, Object?> values) {
      observations.add({
        'size': '${size.cols}x${size.rows}',
        'scenario': scenario,
        ...values,
      });
    }

    void capture(String scenario) {
      final cells = tester.render();
      List<int>? rgb(Color? color) => color == null
          ? null
          : [color.toRgb().r, color.toRgb().g, color.toRgb().b];
      screens.add({
        'label': '$scenario-${size.cols}x${size.rows}',
        'cols': size.cols,
        'rows': size.rows,
        'text': tester.renderToString(emptyMark: ' '),
        'cells': [
          for (var y = 0; y < size.rows; y++)
            [
              for (var x = 0; x < size.cols; x++)
                (() {
                  final c = cells.atColRow(x, y);
                  return [
                    c.grapheme,
                    rgb(c.style.foreground),
                    rgb(c.style.background),
                    c.style.bold,
                    c.style.dim,
                    c.style.inverse,
                    c.style.underline,
                  ];
                })(),
            ],
        ],
      });
    }

    capture('browse');
    observe('browse density', {
      'totalKeys': model.keys.length,
      'visibleRows': tester
          .renderToString()
          .split('\n')
          .where((line) => line.contains('service/'))
          .length,
    });
    observe('automatic list key hints', {
      'labels': resolveActiveKeyBindings(
        tester.focusManager,
      ).map((hint) => hint.binding.displayLabel).toList(),
    });
    await key(KeyCode.arrowDown);
    final selected = model.selectedKey;
    await key(KeyCode.char(' '));
    capture('revealed-second-key');
    await key(KeyCode.arrowRight);
    capture('value-focused');
    await key(KeyCode.escape);
    observe('hide preserves selection', {
      'before': selected,
      'after': model.selectedKey,
    });

    await key(KeyCode.char('/'));
    tester.type('service/2');
    await tester.settle();
    capture('search-focused');
    await key(KeyCode.enter);
    await key(KeyCode.char(' '));
    final query = model.query;
    await key(KeyCode.escape);
    observe('hide preserves filter', {'before': query, 'after': model.query});

    // Explicitly clear the prior query so this scenario is independent of
    // whether the reviewed version preserves it on hide.
    await key(KeyCode.escape);
    await key(KeyCode.char('/'));
    tester.type('service/2');
    await tester.settle();
    await key(KeyCode.enter);
    await key(KeyCode.enter);
    final editingQuery = model.query;
    await key(KeyCode.s, ctrl: true);
    observe('save preserves filter', {
      'before': editingQuery,
      'after': model.query,
      'selected': model.selectedKey,
    });
    tester.pump(const Duration(seconds: 4));
    await tester.settle();

    await key(KeyCode.escape);
    await key(KeyCode.end);
    final tail = model.selectedKey;
    await key(KeyCode.enter);
    await key(KeyCode.escape);
    observe('cancel restores selected row in viewport', {
      'before': tail,
      'after': model.selectedKey,
      'rowVisible': tester.renderToString().contains(tail!),
    });
    capture('cancel-at-end');

    for (var i = 0; i < 7; i++) {
      await key(KeyCode.c);
    }
    final notificationCount = tester
        .semantics()
        .nodes
        .where((node) => node.role == SemanticRole.notification)
        .length;
    observe('repeated copy feedback', {
      'notifications': notificationCount,
      'copyLabelVisible': tester.renderToString().contains('Copy'),
      'quitLabelVisible': tester.renderToString().contains('Quit'),
    });
    capture('seven-copies');
    tester.pump(const Duration(seconds: 4));
    await tester.settle();

    model.message(
      'Copy could not be confirmed. The clipboard may have changed.',
      failure: true,
    );
    await tester.settle();
    capture('copy-failure');
    await key(KeyCode.escape);
    observe('escape dismisses idle error', {
      'stillVisible': tester.renderToString().contains(
        'Copy could not be confirmed.',
      ),
    });
    model.message('An error that needs correction.', failure: true);
    await tester.settle();
    tester.pump(const Duration(seconds: 16));
    await tester.settle();
    observe('error after fifteen seconds', {
      'visible': tester.renderToString().contains(
        'An error that needs correction.',
      ),
      'modelError': model.error,
    });

    await key(KeyCode.n);
    tester.type('bad key');
    await key(KeyCode.enter);
    tester.type('synthetic draft');
    await key(KeyCode.s, ctrl: true);
    final field = tester.semantics().nodes.singleWhere(
      (node) => node.label == 'Key name',
    );
    observe('invalid name semantics', {
      'validationError': field.validationError,
      'focused': field.focused,
      'visibleError': tester.renderToString().contains('Use a name'),
    });
    capture('invalid-name');
    await key(KeyCode.escape);

    await key(KeyCode.char('/'));
    tester.type('missing');
    await tester.settle();
    capture('no-results');
    await key(KeyCode.escape);
    await key(KeyCode.s);
    capture('settings-security');
    await key(KeyCode.tab);
    capture('settings-content');
    await key(KeyCode.p);
    capture('passphrase');
    await key(KeyCode.escape);
    await key(KeyCode.escape);
    await key(KeyCode.d);
    capture('delete');

    tester.dispose();
    await model.close();
    model.dispose();
    await store.dispose();
  }
  // Check the existing framework route before proposing new validation APIs.
  final formTester = FleuryTester();
  final controller = TextEditingController(preserveText: true);
  final form = FormController();
  var submissions = 0;
  formTester.pumpWidget(
    Form(
      controller: form,
      onSubmit: () {
        submissions++;
      },
      child: FormField(
        validator: () =>
            controller.text.contains(' ') ? 'No spaces in key names.' : null,
        child: TextInput(
          controller: controller,
          semanticLabel: 'Key name',
          autofocus: true,
        ),
      ),
    ),
  );
  await formTester.settle();
  formTester.type('bad key');
  await formTester.settle();
  final submitting = form.submit();
  await formTester.settle();
  final accepted = await submitting;
  observations.add({
    'scenario': 'existing Fleury Form validation',
    'accepted': accepted,
    'submissions': submissions,
    'draftPreserved': controller.text == 'bad key',
    'validationError': formTester
        .semantics()
        .single(label: 'Key name')
        .validationError,
    'focused': formTester.semantics().single(label: 'Key name').focused,
  });
  formTester.dispose();
  controller.dispose();
  form.dispose();
  const encoder = JsonEncoder.withIndent('  ');
  if (arguments.isNotEmpty) {
    final output = Directory(arguments.single)..createSync(recursive: true);
    File(
      '${output.path}/observations.json',
    ).writeAsStringSync(encoder.convert(observations));
    File('${output.path}/screens.json').writeAsStringSync(jsonEncode(screens));
  }
  stdout.writeln(encoder.convert(observations));
}
