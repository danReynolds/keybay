import 'dart:ffi';

typedef _NativeGetProcessGroup = Int32 Function();
typedef _DartGetProcessGroup = int Function();
typedef _NativeGetTerminalProcessGroup = Int32 Function(Int32);
typedef _DartGetTerminalProcessGroup = int Function(int);
typedef _NativeIsTerminal = Int32 Function(Int32);
typedef _DartIsTerminal = int Function(int);

final DynamicLibrary _libc = DynamicLibrary.process();
final _DartGetProcessGroup _getpgrp = _libc
    .lookupFunction<_NativeGetProcessGroup, _DartGetProcessGroup>('getpgrp');
final _DartGetTerminalProcessGroup _tcgetpgrp = _libc
    .lookupFunction<
      _NativeGetTerminalProcessGroup,
      _DartGetTerminalProcessGroup
    >('tcgetpgrp');
final _DartIsTerminal _isatty = _libc
    .lookupFunction<_NativeIsTerminal, _DartIsTerminal>('isatty');
final _DartGetTerminalProcessGroup _tcgetsid = _libc
    .lookupFunction<
      _NativeGetTerminalProcessGroup,
      _DartGetTerminalProcessGroup
    >('tcgetsid');
final _DartGetTerminalProcessGroup _getsid = _libc
    .lookupFunction<
      _NativeGetTerminalProcessGroup,
      _DartGetTerminalProcessGroup
    >('getsid');

/// Whether file descriptor [fd] is attached to a terminal.
bool terminalIsAttached(int fd) => _isatty(fd) == 1;

/// Whether file descriptor [fd] belongs to this process's foreground terminal
/// process group.
///
/// Callers first establish that [fd] is a terminal. Keybay supports only the
/// POSIX desktop hosts on which `getpgrp` and `tcgetpgrp` are available.
bool terminalIsForeground(int fd) => _tcgetpgrp(fd) == _getpgrp();

/// A session has only one controlling terminal. Matching the terminal's
/// session ID proves this is that device, including when opened via /dev/tty;
/// isatty/foreground checks alone do not establish this relationship.
bool terminalIsControllingForeground(int fd) =>
    terminalIsAttached(fd) &&
    _tcgetsid(fd) == _getsid(0) &&
    terminalIsForeground(fd);

/// Render caller-controlled paths/arguments without terminal or bidi controls.
/// Quotes and backslashes are escaped so argument boundaries remain legible.
String terminalQuoted(String text) {
  final result = StringBuffer('"');
  for (final rune in text.runes) {
    if (rune == 0x22 || rune == 0x5c) {
      result.write('\\${String.fromCharCode(rune)}');
    } else if (rune < 0x20 || rune > 0x7e) {
      result.write('\\u{${rune.toRadixString(16)}}');
    } else {
      result.writeCharCode(rune);
    }
  }
  return '$result"';
}
