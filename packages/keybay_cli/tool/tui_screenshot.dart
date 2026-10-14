// Documentation screenshots: renders the real TUI and model, with an in-memory
// demo store, to SVG. Never used by the production CLI or release artifacts.
//
//   dart run tool/tui_screenshot.dart tour ../../assets/tui-tour.svg
//   dart run tool/tui_screenshot.dart vault build/tui-vault.svg
//
// `tour` scripts keys through unlock, search, reveal and Settings, and emits an
// SVG whose frames a CSS animation steps through. Viewers that prefer reduced
// motion see the vault frame alone.
import 'dart:convert';
import 'dart:io';

import 'package:fleury/fleury_core.dart';
import 'package:fleury/fleury_test_support.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/native_model.dart';
import 'package:keybay_cli/src/tui/screen.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

// The TUI's smallest wide layout keeps text as large as possible when scaled.
const _size = CellSize(80, 22);
const _scenes = {'vault', 'tour'};
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

typedef _Frame = ({CellBuffer buffer, double seconds, bool poster});

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
  if (scene == 'tour') {
    await seed.auth.add(PassphraseCredential(phrase: utf8.encode(_phrase)));
  }
  await seed.close();

  // The production idle timeout, so Settings shows what users see.
  final model = createNativeTuiModel(
    openSession: store.open,
    resetStore: store.reset,
    authorize: () {},
    copyText: (_) async {},
    onExit: () {},
  );
  final tester = FleuryTester(
    viewportSize: _size,
    animationPolicy: AnimationPolicy.disabled,
  );
  final frames = <_Frame>[];
  Future<void> capture(double seconds, {bool poster = false}) async {
    await tester.settle();
    frames.add((
      buffer: tester.render(size: _size),
      seconds: seconds,
      poster: poster,
    ));
  }

  Future<void> press(KeyCode code) async {
    tester.sendKey(KeyEvent(code));
    await tester.settle();
  }

  try {
    tester.pumpWidget(KeybayTui(model: model));
    await model.open();
    await tester.settle();
    switch (scene) {
      case 'vault':
        // Move the selection off the first row so the highlight reads clearly.
        await press(KeyCode.arrowDown);
        await capture(0);
      case 'tour':
        await capture(0.8);
        for (final chunk in ['demo', ' pas', 'sphr', 'ase']) {
          tester.type(chunk);
          await capture(0.3);
        }
        await press(KeyCode.enter);
        await press(KeyCode.arrowDown);
        await capture(2.4, poster: true);
        await press(KeyCode.char('/'));
        await capture(0.4);
        for (final letter in ['a', 'w', 's']) {
          tester.type(letter);
          await capture(letter == 's' ? 1.1 : 0.3);
        }
        await press(KeyCode.arrowDown);
        await press(KeyCode.arrowDown);
        await capture(0.6);
        await press(KeyCode.char(' '));
        await capture(2.6);
        await press(KeyCode.s);
        await capture(2.2);
    }
    final out = File(arguments[1]);
    out.writeAsStringSync(_svg(frames));
    stdout.writeln(
      'wrote ${out.path}: ${frames.length} frame(s), ${out.lengthSync()} bytes',
    );
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

String _svg(List<_Frame> captured) {
  // Start the loop on the poster, so viewers that show only the first frame,
  // such as link previews, still get the vault.
  final poster = captured.indexWhere((frame) => frame.poster);
  final frames = poster <= 0
      ? captured
      : [...captured.skip(poster), ...captured.take(poster)];
  final width = _size.cols * _cellWidth + 2 * _padding;
  final height = _size.rows * _cellHeight + 2 * _padding + _titleBar;
  final animated = frames.length > 1;
  final total = frames.fold(0.0, (sum, frame) => sum + frame.seconds);
  final out = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${width.round()}" '
      'height="${height.round()}" viewBox="0 0 $width $height" '
      'role="img" aria-label="Keybay terminal interface">',
    );
  if (animated) {
    // step-end holds each keyframe's opacity until the next, so exactly one
    // frame is visible at a time. The poster shows wherever animation is off.
    out
      ..writeln('<style>')
      ..writeln(
        '.f{opacity:0;animation:${total.toStringAsFixed(1)}s step-end infinite}'
        '.poster{opacity:1}',
      );
    var start = 0.0;
    for (final (index, frame) in frames.indexed) {
      final from = _percent(start / total);
      final to = _percent((start + frame.seconds) / total);
      final keyframes = start == 0
          ? '0%{opacity:1}$to%{opacity:0}'
          : '0%{opacity:0}$from%{opacity:1}$to%{opacity:0}';
      out.writeln(
        '@keyframes f$index{$keyframes}.f$index{animation-name:f$index}',
      );
      start += frame.seconds;
    }
    out
      ..writeln('@media (prefers-reduced-motion:reduce){.f{animation:none}}')
      ..writeln('</style>');
  }
  out
    ..writeln(
      '<rect width="$width" height="$height" rx="10" '
      'fill="$_defaultBackground"/>',
    )
    ..writeln(
      '<circle cx="20" cy="15" r="6" fill="#ff5f56"/>'
      '<circle cx="40" cy="15" r="6" fill="#ffbd2e"/>'
      '<circle cx="60" cy="15" r="6" fill="#27c93f"/>'
      '<text x="${width / 2}" y="19" text-anchor="middle" fill="#8b949e" '
      'font-family="SF Mono, Menlo, Consolas, DejaVu Sans Mono, monospace" '
      'font-size="12">keybay open</text>',
    );
  for (final (index, frame) in frames.indexed) {
    final classes = [
      if (animated) ...['f', 'f$index'],
      if (animated && frame.poster) 'poster',
    ];
    out
      ..write(
        '<g font-family="SF Mono, Menlo, Consolas, DejaVu Sans Mono, '
        'monospace" font-size="14" xml:space="preserve"',
      )
      ..write(classes.isEmpty ? '' : ' class="${classes.join(' ')}"')
      ..writeln('>')
      ..write(_cells(frame.buffer))
      ..writeln('</g>');
  }
  out.writeln('</svg>');
  return out.toString();
}

String _percent(double fraction) =>
    (fraction * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

typedef _Word = ({List<double> xs, StringBuffer text, String attributes});

/// One frame's cells. Adjacent cells sharing a style become one element: a
/// rect per background run, one path per border color, and a text element per
/// word with an explicit x for every glyph, so alignment never depends on the
/// viewer's font.
String _cells(CellBuffer buffer) {
  final out = StringBuffer();
  final strokes = <String, StringBuffer>{};
  for (var row = 0; row < buffer.size.rows; row++) {
    final y = _padding + _titleBar + row * _cellHeight;
    final textY = y + _cellHeight * 0.72;
    ({double start, double end, String fill})? run;
    _Word? word;
    final words = <_Word>[];
    void endRun() {
      if (run case (:final start, :final end, :final fill)) {
        out.writeln(
          '<rect x="$start" y="$y" width="${end - start + 0.5}" '
          'height="${_cellHeight + 0.5}" fill="$fill"/>',
        );
      }
      run = null;
    }

    void endWord() {
      if (word != null) words.add(word!);
      word = null;
    }

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
      final end = x + _cellWidth * (wide ? 2 : 1);
      final glyph = cell.role == CellRole.leading ? cell.grapheme : null;

      final fill = glyph == '█'
          ? foreground
          : background == _defaultBackground
          ? null
          : background;
      if (fill != run?.fill) endRun();
      if (fill != null) run = (start: run?.start ?? x, end: end, fill: fill);

      if (glyph == null || glyph.trim().isEmpty || glyph == '█') {
        endWord();
        continue;
      }
      if (_boxArms[glyph] case final arms?) {
        endWord();
        final cx = (x + end) / 2;
        final cy = y + _cellHeight / 2;
        final path = strokes.putIfAbsent(foreground, StringBuffer.new);
        if (arms.contains('l')) path.write('M$cx ${cy}H$x');
        if (arms.contains('r')) path.write('M$cx ${cy}H$end');
        if (arms.contains('u')) path.write('M$cx ${cy}V$y');
        if (arms.contains('d')) path.write('M$cx ${cy}V${y + _cellHeight}');
        continue;
      }
      final attributes = [
        'fill="$foreground"',
        if (style.bold) 'font-weight="bold"',
        if (style.italic) 'font-style="italic"',
        if (style.underline) 'text-decoration="underline"',
      ].join(' ');
      if (attributes != word?.attributes) endWord();
      word ??= (xs: [], text: StringBuffer(), attributes: attributes);
      word!.xs.add(x);
      word!.text.write(glyph);
    }
    endRun();
    endWord();
    for (final (:xs, :text, :attributes) in words) {
      out.writeln(
        '<text x="${xs.join(' ')}" y="$textY" $attributes>'
        '${_escape(text.toString())}</text>',
      );
    }
  }
  for (final MapEntry(key: color, value: path) in strokes.entries) {
    out.writeln(
      '<path d="$path" stroke="$color" stroke-width="1.5" '
      'stroke-linecap="square" fill="none"/>',
    );
  }
  return out.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
