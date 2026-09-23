import 'dart:ffi';
import 'dart:io';

// Native numbers for libc. Dart's ProcessSignal.signalNumber is Dart's own
// identifier in Linux numbering, which the runtime translates only for its own
// APIs: on Darwin SIGTSTP is 18, and Dart's 20 would name SIGCHLD there.
// SIGQUIT, SIGTTIN and SIGTTOU share their numbers on every supported host
// (Darwin, Linux/glibc, and Android/bionic).
const int _sigQuit = 3;
final int _sigTstp = Platform.isMacOS ? 18 : 20;
const int _sigTtin = 21;
const int _sigTtou = 22;

/// Ignores signals Dart cannot observe while Keybay owns the terminal.
///
/// Dart exposes no SIGQUIT or job-control signal streams, so no cleanup can run
/// for them. Their defaults would stop or core-dump the process with the
/// terminal still in raw mode, possibly showing a revealed value. Keybay never
/// suspends with secret input or an open session: in raw mode Ctrl+Z and
/// Ctrl+\ arrive as input, and an external stop request is ignored. Restores
/// the previous dispositions on [close]. SIGSTOP and SIGKILL remain uncatchable.
/// This extends the contract the owner ratified for hidden input (implementation
/// plan §15) instead of adding a native signal bridge.
final class IgnoredSignals {
  IgnoredSignals.terminalOwnership()
    : signalNumbers = [_sigQuit, _sigTstp, _sigTtin, _sigTtou];

  final List<int> signalNumbers;
  _DartSignal? _signal;
  final Map<int, Pointer<Void>> _previous = <int, Pointer<Void>>{};

  void start() {
    final signal = DynamicLibrary.process()
        .lookupFunction<_NativeSignal, _DartSignal>('signal');
    _signal = signal;
    for (final signalNumber in signalNumbers) {
      _previous[signalNumber] = signal(
        signalNumber,
        Pointer<Void>.fromAddress(1), // SIG_IGN
      );
    }
  }

  void close() {
    final signal = _signal;
    if (signal != null) {
      for (final entry in _previous.entries) {
        signal(entry.key, entry.value);
      }
    }
    _signal = null;
    _previous.clear();
  }
}

typedef _NativeSignal = Pointer<Void> Function(Int32, Pointer<Void>);
typedef _DartSignal = Pointer<Void> Function(int, Pointer<Void>);
