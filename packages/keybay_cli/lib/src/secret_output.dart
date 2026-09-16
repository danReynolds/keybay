import 'terminal.dart';

final class SecretOutputException implements Exception {
  const SecretOutputException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SecretOutputTerminal {
  bool get outputHasTerminal;
  bool get outputIsControllingForeground;
}

/// Authorizes the narrow, human-visible `get` output path.
///
/// Stdout must be the controlling foreground terminal. Stdin is unconsumed
/// and need not be a terminal. Check before opening and immediately at reveal.
final class SecretOutputGuard {
  SecretOutputGuard(this.terminal);

  factory SecretOutputGuard.system() =>
      SecretOutputGuard(const _SystemSecretOutputTerminal());

  final SecretOutputTerminal terminal;

  void authorize() {
    if (!terminal.outputHasTerminal) {
      throw const SecretOutputException(
        'get requires the controlling TTY on stdout; redirected or '
        'captured output is refused (use keybay run to provide a secret to a '
        'program)',
      );
    }
    if (!terminal.outputIsControllingForeground) {
      throw const SecretOutputException(
        'get must write to its controlling foreground TTY; foreground the job and retry',
      );
    }
  }
}

/// Refuses terminal control characters that could alter the display rather
/// than represent the value literally.
///
/// Every C0/C1 and Unicode bidirectional control is unsafe to emit as raw
/// terminal text. Multiline values belong in the future framed TUI view.
bool secretIsSafeForTerminal(String value) {
  for (final rune in value.runes) {
    final unsafeC0 = rune < 0x20;
    final unsafeC1 = rune >= 0x7f && rune <= 0x9f;
    final bidiControl =
        rune == 0x061c ||
        rune == 0x200e ||
        rune == 0x200f ||
        (rune >= 0x202a && rune <= 0x202e) ||
        (rune >= 0x2066 && rune <= 0x2069);
    if (unsafeC0 || unsafeC1 || bidiControl) return false;
  }
  return true;
}

final class _SystemSecretOutputTerminal implements SecretOutputTerminal {
  const _SystemSecretOutputTerminal();

  @override
  bool get outputHasTerminal => terminalIsAttached(1);

  @override
  bool get outputIsControllingForeground => terminalIsControllingForeground(1);
}
