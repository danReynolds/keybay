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

/// Whether file descriptor [fd] is attached to a terminal.
bool terminalIsAttached(int fd) => _isatty(fd) == 1;

/// Whether file descriptor [fd] belongs to this process's foreground terminal
/// process group.
///
/// Callers first establish that [fd] is a terminal. Keybay supports only the
/// POSIX desktop hosts on which `getpgrp` and `tcgetpgrp` are available.
bool terminalIsForeground(int fd) => _tcgetpgrp(fd) == _getpgrp();
