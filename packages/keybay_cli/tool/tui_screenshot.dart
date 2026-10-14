// Documentation screenshots: renders the real TUI and model, with an in-memory
// demo store, to SVG. Never used by the production CLI or release artifacts.
//
//   dart run tool/tui_screenshot.dart vault ../../assets/tui-vault.svg
//   dart run tool/tui_screenshot.dart unlock ../../assets/tui-unlock.svg
//   dart run tool/tui_screenshot.dart security ../../assets/tui-security.svg
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

const _size = CellSize(88, 24);
const _scenes = {'vault', 'unlock', 'security'};
const _phrase = 'demo passphrase';

const _records = {
  'acme/api-key': 'demo_acme_key_for_docs',
  'acme/database-url': 'postgres://demo:example@localhost:5432/acme_dev',
  'anthropic/api-key': 'sk-ant-demo-not-a-real-key',
  'aws/access-key-id': 'AKIA_DEMO_ONLY',
  'aws/secret-access-key': 'example-aws-secret-for-docs',
  'cloudflare/api-token': 'demo-cloudflare-token',
  'github/token': 'ghp_demo_not_a_real_token',
  'npm/publish-token': 'npm_demo_not_a_real_token',
  'openai/api-key': 'sk-demo-not-a-real-key',
  'sentry/dsn': 'https://demo@example.ingest.sentry.io/0',
  'slack/bot-token': 'xoxb-demo-not-a-real-token',
  'stripe/test-key': 'sk_test_demo_for_docs',
  'twilio/auth-token': 'demo-twilio-token',
  'webhook/signing-secret': 'whsec_demo_not_a_real_secret',
};

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || !_scenes.contains(arguments[0])) {
    stderr.writeln(
      'usage: tui_screenshot.dart ${_scenes.join('|')} <output.svg>',
    );
    exitCode = 64;
    return;
  }
  final scene = arguments[0];
  final store = V2TestKeybay(applicationId: 'dev.keybay.tui-screenshot');
  final seed = await store.open();
  for (final entry in _records.entries) {
    await seed.set(entry.key, entry.value);
  }
  if (scene != 'vault') {
    await seed.auth.add(PassphraseCredential(phrase: utf8.encode(_phrase)));
  }
  await seed.close();

  final model = createNativeTuiModel(
    openSession: store.open,
    resetStore: store.reset,
    authorize: () {},
    copyText: (_) async {},
    onExit: () {},
    idleTimeout: null,
  );
  final tester = FleuryTester(
    viewportSize: _size,
    animationPolicy: AnimationPolicy.disabled,
  );
  try {
    tester.pumpWidget(KeybayTui(model: model));
    await model.open();
    await tester.settle();
    switch (scene) {
      case 'vault':
        // Move the selection off the first row so the highlight reads clearly.
        tester.sendKey(const KeyEvent(KeyCode.arrowDown));
      case 'security':
        tester.type(_phrase);
        tester.sendKey(const KeyEvent(KeyCode.enter));
        await tester.settle();
        tester.sendKey(const KeyEvent(KeyCode.s));
        await tester.settle();
        model.navigate(TuiView.security);
    }
    await tester.settle();
    File(arguments[1]).writeAsStringSync(_svg(tester.render(size: _size)));
  } finally {
    tester.dispose();
    await model.close();
    model.dispose();
    await store.dispose();
  }
}

// A neutral dark palette for the 16 ANSI colors; RGB colors pass through.
const _ansi = [
  '#1e1e1e', '#f14c4c', '#23d18b', '#e5c07b', '#3b8eea', '#d670d6', '#29b8db',
  '#d4d4d4', '#808080', '#f14c4c', '#23d18b', '#f5f543', '#3b8eea', '#d670d6',
  '#29b8db', '#ffffff', //
];
const _defaultForeground = '#d4d4d4';
const _defaultBackground = '#1e1e1e';
const _cellWidth = 8.4;
const _cellHeight = 19.0;
const _padding = 16.0;
const _titleBar = 28.0;

String _hex(Color? color, String fallback) => switch (color) {
  null => fallback,
  AnsiColor(:final index) => _ansi[index],
  final color => () {
    final rgb = color.toRgb();
    return _rgbHex(rgb.r, rgb.g, rgb.b);
  }(),
};

String _rgbHex(int r, int g, int b) =>
    '#${[r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';

/// Blends instead of using opacity, so overlapping border strokes stay even.
String _dim(String foreground, String background) {
  int channel(String hex, int i) =>
      int.parse(hex.substring(1 + 2 * i, 3 + 2 * i), radix: 16);
  int mix(int i) =>
      (channel(foreground, i) * 0.6 + channel(background, i) * 0.4).round();
  return _rgbHex(mix(0), mix(1), mix(2));
}

// Box-drawing glyphs as arms from the cell center, drawn as strokes so borders
// join regardless of the viewer's font metrics.
const _boxArms = {
  '─': 'lr', '│': 'ud', '┌': 'rd', '╭': 'rd', '┐': 'ld', '╮': 'ld', //
  '└': 'ru', '╰': 'ru', '┘': 'lu', '╯': 'lu', '├': 'udr', '┤': 'udl',
  '┬': 'lrd', '┴': 'lru', '┼': 'lrud',
};

String _svg(CellBuffer buffer) {
  final width = buffer.size.cols * _cellWidth + 2 * _padding;
  final height = buffer.size.rows * _cellHeight + 2 * _padding + _titleBar;
  final out = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${width.round()}" '
      'height="${height.round()}" viewBox="0 0 $width $height" '
      'role="img" aria-label="Keybay terminal interface">',
    )
    ..writeln(
      '<rect width="$width" height="$height" rx="10" '
      'fill="$_defaultBackground"/>',
    )
    ..writeln(
      '<circle cx="20" cy="15" r="6" fill="#ff5f56"/>'
      '<circle cx="40" cy="15" r="6" fill="#ffbd2e"/>'
      '<circle cx="60" cy="15" r="6" fill="#27c93f"/>',
    )
    ..writeln(
      '<g font-family="SF Mono, Menlo, Consolas, DejaVu Sans Mono, monospace" '
      'font-size="14" xml:space="preserve">',
    );
  for (var row = 0; row < buffer.size.rows; row++) {
    final y = _padding + _titleBar + row * _cellHeight;
    for (var col = 0; col < buffer.size.cols; col++) {
      final cell = buffer.atColRow(col, row);
      if (cell.role == CellRole.continuation) continue;
      final style = cell.style;
      var foreground = _hex(style.foreground, _defaultForeground);
      var background = _hex(style.background, _defaultBackground);
      if (style.inverse) (foreground, background) = (background, foreground);
      if (style.dim) foreground = _dim(foreground, background);
      final x = _padding + col * _cellWidth;
      final wide =
          col + 1 < buffer.size.cols &&
          buffer.atColRow(col + 1, row).role == CellRole.continuation;
      final cellWidth = _cellWidth * (wide ? 2 : 1);
      if (background != _defaultBackground) {
        out.writeln(_rect(x, y, cellWidth, background));
      }
      final glyph = cell.role == CellRole.leading ? cell.grapheme : null;
      if (glyph == null || glyph.trim().isEmpty) continue;
      if (glyph == '█') {
        out.writeln(_rect(x, y, cellWidth, foreground));
        continue;
      }
      if (_boxArms[glyph] case final arms?) {
        final cx = x + cellWidth / 2;
        final cy = y + _cellHeight / 2;
        final path = [
          if (arms.contains('l')) 'M$cx ${cy}H$x',
          if (arms.contains('r')) 'M$cx ${cy}H${x + cellWidth}',
          if (arms.contains('u')) 'M$cx ${cy}V$y',
          if (arms.contains('d')) 'M$cx ${cy}V${y + _cellHeight}',
        ].join();
        out.writeln(
          '<path d="$path" stroke="$foreground" stroke-width="1.5" '
          'stroke-linecap="square" fill="none"/>',
        );
        continue;
      }
      final attributes = [
        'x="$x"',
        'y="${y + _cellHeight * 0.72}"',
        'fill="$foreground"',
        if (style.bold) 'font-weight="bold"',
        if (style.italic) 'font-style="italic"',
        if (style.underline) 'text-decoration="underline"',
      ].join(' ');
      out.writeln('<text $attributes>${_escape(glyph)}</text>');
    }
  }
  out
    ..writeln('</g>')
    ..writeln('</svg>');
  return out.toString();
}

String _rect(double x, double y, double width, String fill) =>
    '<rect x="$x" y="$y" width="${width + 0.5}" height="${_cellHeight + 0.5}" '
    'fill="$fill"/>';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
