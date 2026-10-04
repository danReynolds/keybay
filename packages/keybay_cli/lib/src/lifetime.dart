import 'dart:async';
import 'dart:io';

/// One invocation owns cancellation. SDK work is awaited, never raced against
/// cancellation; only input waits are interruptible. No state survives exit.
final class CommandLifetime {
  final Completer<void> _cancelled = Completer<void>();
  final List<StreamSubscription<ProcessSignal>> _signals = [];
  int? _status;
  final Set<void Function()> _cancelListeners = {};

  Future<void> get cancelled => _cancelled.future;

  /// Return a remover so completed operations do not retain native callbacks.
  void Function() onCancel(void Function() listener) {
    if (_status != null) {
      listener();
      return () {};
    }
    _cancelListeners.add(listener);
    return () => _cancelListeners.remove(listener);
  }

  void start() {
    for (final signal in [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sighup,
    ]) {
      _signals.add(
        signal.watch().listen((_) => cancel(128 + signal.signalNumber)),
      );
    }
  }

  void cancel([int status = 130]) {
    if (_status != null) return;
    _status = status;
    for (final listener in List.of(_cancelListeners)) {
      listener();
    }
    _cancelListeners.clear();
    _cancelled.complete();
  }

  void check() {
    if (_status case final status?) throw CommandInterrupted(status);
  }

  Future<void> close() async {
    for (final signal in _signals) {
      await signal.cancel();
    }
    _signals.clear();
  }
}

final class CommandInterrupted implements Exception {
  const CommandInterrupted(this.exitCode);
  final int exitCode;
}
