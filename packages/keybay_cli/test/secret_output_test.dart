import 'package:keybay_cli/src/secret_output.dart';
import 'package:test/test.dart';

void main() {
  group('secret output guard', () {
    test('authorizes only when stdout owns the controlling foreground TTY', () {
      final terminal = _FakeSecretOutputTerminal();

      SecretOutputGuard(terminal).authorize();

      expect(terminal.foregroundReads, 1);
    });

    test('refuses redirected or captured streams before foreground probes', () {
      for (final terminal in <_FakeSecretOutputTerminal>[
        _FakeSecretOutputTerminal(outputHasTerminal: false),
      ]) {
        expect(
          () => SecretOutputGuard(terminal).authorize(),
          throwsA(
            isA<SecretOutputException>().having(
              (error) => error.message,
              'message',
              allOf(contains('controlling TTY'), contains('captured')),
            ),
          ),
        );
        expect(terminal.foregroundReads, 0);
      }
    });

    test('refuses background or unrelated terminal output', () {
      for (final terminal in <_FakeSecretOutputTerminal>[
        _FakeSecretOutputTerminal(outputIsControllingForeground: false),
      ]) {
        expect(
          () => SecretOutputGuard(terminal).authorize(),
          throwsA(
            isA<SecretOutputException>().having(
              (error) => error.message,
              'message',
              contains('foreground'),
            ),
          ),
        );
      }
    });
  });

  test('terminal value validation allows plain text but rejects controls', () {
    expect(secretIsSafeForTerminal('plain unicode text é'), isTrue);
    expect(
      secretIsSafeForTerminal('accent e\u0301 and emoji \u2764\ufe0f'),
      isTrue,
    );
    expect(secretIsSafeForTerminal('keycap 1\ufe0f\u20e3 \\ ok'), isTrue);
    for (final value in <String>[
      'line one\nline two',
      'tab\tvalue',
      'escape\u001b[31m',
      'backspace\b',
      'c1\u009b31m',
      'bidi\u202eoverride',
      'zero\u200bwidth',
      'soft\u00adhyphen',
      'prepend\u0600mark',
      'bom\ufeff',
      'tag\u{e0041}',
      'separator\u2028line',
      // Exactly what the TUI shows escaped: marks and selectors that would
      // draw nothing or hide behind a character, and prepended letters.
      '\u0301abc',
      '\ufe0fabc',
      'pa\ufe0ess',
      'a\u{e0100}',
      '\u0d4esecret',
    ]) {
      expect(secretIsSafeForTerminal(value), isFalse, reason: value);
    }
  });
}

final class _FakeSecretOutputTerminal implements SecretOutputTerminal {
  _FakeSecretOutputTerminal({
    this.outputHasTerminal = true,
    bool outputIsControllingForeground = true,
  }) : _foreground = outputIsControllingForeground;
  @override
  final bool outputHasTerminal;
  final bool _foreground;
  int foregroundReads = 0;
  @override
  bool get outputIsControllingForeground {
    foregroundReads++;
    return _foreground;
  }
}
