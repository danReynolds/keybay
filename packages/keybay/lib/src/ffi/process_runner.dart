/// A minimal, injectable subprocess runner for the CLI-backed seam
/// (`secret-tool` on Linux).
///
/// Injectable so backend logic is testable without the real binary. Output is
/// captured as raw bytes because it can echo secret material; callers parse
/// what they need, zero the buffers, and must never attach them to an error.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

/// Outcome of a subprocess run.
final class ProcessRunResult {
  ProcessRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.launchFailed,
    this.outputLimitExceeded = false,
  });

  final int exitCode;

  /// Raw stdout bytes. May carry secret material.
  final Uint8List stdout;

  /// Raw stderr bytes. Same handling rule as [stdout].
  final Uint8List stderr;

  final bool timedOut;

  /// The executable could not be launched (e.g. not installed).
  final bool launchFailed;

  /// The child produced more output than the runner is willing to retain.
  ///
  /// Output can contain secret material. Treat this as an operation failure,
  /// never as a truncated-but-otherwise-valid response.
  final bool outputLimitExceeded;
}

/// Maximum bytes retained from each subprocess stream.
///
/// `secret-tool search` can echo every matching secret, so an unbounded
/// collector lets a noisy or compromised PATH-resolved helper exhaust the
/// caller's memory. Sixteen MiB per stream is far above legitimate Keybay
/// responses while keeping the failure deterministic.
const int maxProcessOutputBytes = 16 * 1024 * 1024;

/// Runs a subprocess with optional stdin and a hard timeout.
abstract interface class ProcessRunner {
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? stdin,
    required Duration timeout,
  });
}

/// The real runner over `dart:io`.
final class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner({
    this.maxOutputBytes = maxProcessOutputBytes,
  }) : assert(maxOutputBytes > 0);

  final int maxOutputBytes;

  @override
  Future<ProcessRunResult> run(
    String executable,
    List<String> args, {
    String? stdin,
    required Duration timeout,
  }) async {
    Process proc;
    try {
      proc = await Process.start(executable, args);
    } on ProcessException {
      return ProcessRunResult(
          exitCode: -1,
          stdout: Uint8List(0),
          stderr: Uint8List(0),
          timedOut: false,
          launchFailed: true,
          outputLimitExceeded: false);
    }
    // Start draining stdout/stderr before touching stdin so a chatty child
    // can't deadlock on a full pipe. The builders live out here so the
    // bounded wait below can return whatever bytes arrived even when EOF
    // never comes.
    var outputLimitExceeded = false;
    void onLimitExceeded() {
      outputLimitExceeded = true;
      // Stop the direct child promptly. A grandchild can retain the pipe, so
      // subscriptions are also cancelled after the bounded drain below.
      proc.kill(ProcessSignal.sigkill);
    }

    final out = _CappedOutput(maxOutputBytes, onLimitExceeded);
    final err = _CappedOutput(maxOutputBytes, onLimitExceeded);
    final outDrain = _StreamDrain(proc.stdout, out.add)..start();
    final errDrain = _StreamDrain(proc.stderr, err.add)..start();

    // Arm the hard timeout *before* touching stdin: a child that never drains
    // its stdin can block flush() past the OS pipe buffer, so the timer must
    // already be able to fire (and SIGKILL it) during the write, not only
    // while awaiting exit.
    var timedOut = false;
    final timer = Timer(timeout, () {
      // kill() returns false when the child already exited — a run that
      // finished just before the deadline must not be reported as timed out.
      timedOut = proc.kill(ProcessSignal.sigkill);
    });
    try {
      if (stdin != null) {
        proc.stdin.write(stdin);
      }
      await proc.stdin.flush();
      await proc.stdin.close();
    } on Object {
      // Broken pipe (child exited or was killed without reading stdin). The
      // exit code / timedOut flag tell the story; don't let it escape untyped.
    }

    final code = await proc.exitCode;
    timer.cancel();
    // Bounded drain: the pipes hit EOF the instant the child dies — unless a
    // grandchild inherited the write ends (a forked helper), which our
    // SIGKILL of the direct child cannot reach. Waiting only a grace period
    // past exit preserves the no-hang contract; the builders still hold every
    // byte that actually arrived.
    await Future.wait(<Future<void>>[
      outDrain.finishWithin(_drainGrace),
      errDrain.finishWithin(_drainGrace),
    ]);
    return ProcessRunResult(
        exitCode: code,
        stdout: out.takeBytes(),
        stderr: err.takeBytes(),
        timedOut: timedOut,
        launchFailed: false,
        outputLimitExceeded: outputLimitExceeded);
  }

  /// How long to wait for stdout/stderr EOF after the child has exited.
  static const _drainGrace = Duration(seconds: 2);
}

final class _CappedOutput {
  _CappedOutput(this.limit, this.onLimitExceeded);

  final int limit;
  final void Function() onLimitExceeded;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  var _exceeded = false;

  void add(List<int> chunk) {
    final remaining = limit - _bytes.length;
    if (remaining > 0) {
      _bytes.add(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
    }
    if (!_exceeded && chunk.length > remaining) {
      _exceeded = true;
      onLimitExceeded();
    }
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

/// Owns a stream subscription so a timed-out post-exit drain can be cancelled.
///
/// `Future.timeout` alone leaves the underlying subscription alive; a forked
/// helper that inherited the pipe could then keep appending in the background.
final class _StreamDrain {
  _StreamDrain(this.stream, this.onData);

  final Stream<List<int>> stream;
  final void Function(List<int>) onData;
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;

  void start() {
    _subscription = stream.listen(
      onData,
      onError: (_) {
        if (!_done.isCompleted) _done.complete();
      },
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
      cancelOnError: true,
    );
  }

  Future<void> finishWithin(Duration grace) async {
    var completed = false;
    await Future.any<void>(<Future<void>>[
      _done.future.whenComplete(() => completed = true),
      Future<void>.delayed(grace),
    ]);
    if (!completed) {
      await _subscription.cancel();
    }
  }
}
