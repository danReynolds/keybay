import 'package:keybay_cli/src/secret_output.dart';
import 'package:test/test.dart';

void main() {
  group('secret output guard', () {
    test('authorizes only when both streams own the foreground TTY', () {
      final terminal = _FakeSecretOutputTerminal();

      SecretOutputGuard(terminal).authorize();

      expect(terminal.foregroundReads, 2);
    });

    test('refuses redirected or captured streams before foreground probes', () {
      for (final terminal in <_FakeSecretOutputTerminal>[
        _FakeSecretOutputTerminal(inputHasTerminal: false),
        _FakeSecretOutputTerminal(outputHasTerminal: false),
      ]) {
        expect(
          () => SecretOutputGuard(terminal).authorize(),
          throwsA(
            isA<SecretOutputException>().having(
              (error) => error.message,
              'message',
              allOf(contains('interactive TTY'), contains('captured')),
            ),
          ),
        );
        expect(terminal.foregroundReads, 0);
      }
    });

    test('refuses background input or output', () {
      for (final terminal in <_FakeSecretOutputTerminal>[
        _FakeSecretOutputTerminal(inputIsForeground: false),
        _FakeSecretOutputTerminal(outputIsForeground: false),
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
    for (final value in <String>[
      'line one\nline two',
      'tab\tvalue',
      'escape\u001b[31m',
      'backspace\b',
      'c1\u009b31m',
      'bidi\u202eoverride',
    ]) {
      expect(secretIsSafeForTerminal(value), isFalse, reason: value);
    }
  });
}

final class _FakeSecretOutputTerminal implements SecretOutputTerminal {
  _FakeSecretOutputTerminal({
    this.inputHasTerminal = true,
    this.outputHasTerminal = true,
    bool inputIsForeground = true,
    bool outputIsForeground = true,
  }) : _inputIsForeground = inputIsForeground,
       _outputIsForeground = outputIsForeground;

  @override
  final bool inputHasTerminal;
  @override
  final bool outputHasTerminal;
  final bool _inputIsForeground;
  final bool _outputIsForeground;
  int foregroundReads = 0;

  @override
  bool get inputIsForeground {
    foregroundReads++;
    return _inputIsForeground;
  }

  @override
  bool get outputIsForeground {
    foregroundReads++;
    return _outputIsForeground;
  }
}
