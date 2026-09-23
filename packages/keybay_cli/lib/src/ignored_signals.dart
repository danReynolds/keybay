import 'dart:ffi';
import 'dart:io';

/// Native signal numbers for libc. Dart's `ProcessSignal.signalNumber` is its
/// own identifier in Linux numbering, which the runtime translates only for its
/// own APIs: on Darwin SIGTSTP is 18, and Dart's 20 would name SIGCHLD there.
/// SIGQUIT, SIGTTIN and SIGTTOU share their numbers on every supported host
/// (Darwin, Linux/glibc, and Android/bionic).
abstract final class NativeSignal {
  static const int quit = 3;
  static final int tstp = Platform.isMacOS ? 18 : 20;
  static const int ttin = 21;
  static const int ttou = 22;
}

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
  IgnoredSignals.terminalOwnership();

  final Map<int, Pointer<Void>> _previous = <int, Pointer<Void>>{};

  void start() {
    for (final number in [
      NativeSignal.quit,
      NativeSignal.tstp,
      NativeSignal.ttin,
      NativeSignal.ttou,
    ]) {
      // A second start keeps the dispositions from before the first.
      _previous.putIfAbsent(
        number,
        () => _signal(number, Pointer<Void>.fromAddress(1)), // SIG_IGN
      );
    }
  }

  void close() {
    _previous.forEach(_signal);
    _previous.clear();
  }
}

final Pointer<Void> Function(int, Pointer<Void>) _signal =
    DynamicLibrary.process().lookupFunction<
      Pointer<Void> Function(Int32, Pointer<Void>),
      Pointer<Void> Function(int, Pointer<Void>)
    >('signal');
