import 'display_safety.dart';
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

/// Refuses anything that could alter the display rather than represent the
/// value literally: exactly what the TUI shows escaped (controls, separators,
/// invisible and prepended characters, stray selectors and marks), plus the
/// line feed, which `get` never prints. Such values belong in the TUI's framed,
/// escaped value view.
bool secretIsSafeForTerminal(String value) =>
    !needsTuiEscaping(value, allowNewlines: false);

final class _SystemSecretOutputTerminal implements SecretOutputTerminal {
  const _SystemSecretOutputTerminal();

  @override
  bool get outputHasTerminal => terminalIsAttached(1);

  @override
  bool get outputIsControllingForeground => terminalIsControllingForeground(1);
}
