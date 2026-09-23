import 'dart:async';
import 'dart:developer' show Service;
import 'dart:io';

import 'package:fleury/fleury.dart';

import '../application.dart' show SessionOpener, exitFailure;
import '../ignored_signals.dart';
import '../secret_output.dart';
import '../terminal.dart';
import 'clipboard.dart';
import 'model.dart';
import 'native_model.dart';
import 'screen.dart';

bool tuiForeground() =>
    terminalIsControllingForeground(0) && terminalIsControllingForeground(1);

void authorizeTui() {
  if (!tuiForeground()) {
    throw const SecretOutputException(
      'keybay open requires stdin and stdout on the foreground controlling terminal',
    );
  }
}

/// Native terminal ownership lives here; the model only owns the SDK session.
/// An injected driver disables Fleury's remote selection/output redirection.
Future<int> runTui({
  required SessionOpener openSession,
  required Future<void> Function() resetStore,
  Duration idleTimeout = tuiIdleTimeout,
  Duration idleWarning = tuiIdleWarning,
}) async {
  authorizeTui();
  if (Platform.environment.entries.any(
        (e) => e.key.startsWith('FLEURY_') && e.value.isNotEmpty,
      ) ||
      (await Service.getInfo()).serverUri != null) {
    throw const SecretOutputException(
      'disable Fleury capture/remote/developer settings and the Dart VM service before opening Keybay',
    );
  }
  authorizeTui();
  late final TuiModel model;
  Timer? idle;
  Timer? warning;
  void stop([int code = 0]) => unawaited(model.close(code: code));
  // Say the session is about to end rather than letting the terminal go blank
  // mid-read. The deadline itself does not move.
  void activity() {
    idle?.cancel();
    warning?.cancel();
    final announceAt = idleTimeout - idleWarning;
    if (announceAt > Duration.zero) {
      warning = Timer(
        announceAt,
        () => model.message(
          'Closing soon without input.',
          scope: TuiView.closing,
        ),
      );
    }
    idle = Timer(idleTimeout, stop);
  }

  model = createNativeTuiModel(
    openSession: openSession,
    resetStore: resetStore,
    authorize: authorizeTui,
    copyText: systemCopy(),
    onExit: requestExit,
    idleTimeout: idleTimeout,
  );
  bool accept(TuiEvent event) {
    if (!tuiForeground()) {
      stop(1);
      return false;
    }
    if (event is SignalEvent) {
      stop(event.signal == AppSignal.interrupt ? 130 : 143);
      return false;
    }
    final key = switch (event) {
      KeyEvent() => event,
      InputBatch(:final key) => key,
      _ => null,
    };
    if (key != null &&
        key.hasCtrl &&
        (key.code == KeyCode.char('c') || key.code == KeyCode.char('z'))) {
      stop(key.code == KeyCode.char('c') ? 130 : 0);
      return false;
    }
    if (model.ending) return false;
    if (event is ResizeEvent || event is TerminalFocusEvent && !event.focused) {
      model.conceal();
    } else if (event is KeyEvent ||
        event is TextInputEvent ||
        event is PasteEvent ||
        event is InputBatch ||
        event is TextCompositionEvent ||
        event is MouseEvent && event.kind != MouseEventKind.moved) {
      activity();
    }
    return true;
  }

  final driver = _ForegroundDriver(
    PosixTerminalDriver(suspendOnCtrlZ: false),
    accept,
    () => stop(1),
    () {
      activity();
      unawaited(model.open());
    },
  );
  final hangup = ProcessSignal.sighup.watch().listen((_) => stop(129));
  final foreground = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (!tuiForeground()) stop(1);
  });
  // No stop or core dump while the screen or session may hold a secret.
  final unobservable = IgnoredSignals.terminalOwnership()..start();
  try {
    await runApp(
      KeybayTui(model: model),
      driver: driver,
      mode: const TerminalMode(mouse: true, mouseMotion: true),
      enableHotReload: false,
      debug: const DebugConfig(enabled: false),
      clipboard: DiscardClipboard(),
      onStrayOutput: (_) {},
    );
    return model.exitCode;
  } on Object {
    return exitFailure;
  } finally {
    idle?.cancel();
    warning?.cancel();
    foreground.cancel();
    await hangup.cancel();
    try {
      await model.close();
      model.dispose();
    } finally {
      unobservable.close();
    }
  }
}

/// Recheck immediately before every frame, not only before a secret read. A
/// backgrounded terminal must not receive a pending plaintext repaint.
final class _ForegroundDriver implements TerminalDriver {
  _ForegroundDriver(this.inner, this.accept, this.lost, this.ready);
  final bool Function(TuiEvent) accept;
  final TerminalDriver inner;
  final void Function() lost;
  final void Function() ready;
  @override
  CellSize get size => inner.size;
  @override
  TerminalCapabilities get capabilities => inner.capabilities;
  @override
  Stream<TuiEvent> get events => inner.events.where(accept);
  @override
  bool get isActive => inner.isActive;
  @override
  bool get isInteractive => inner.isInteractive;
  @override
  Future<TerminalSessionProfile> enter(TerminalMode mode) async {
    authorizeTui();
    final profile = await inner.enter(mode);
    authorizeTui();
    scheduleMicrotask(ready);
    return profile;
  }

  @override
  Future<void> restore() => inner.restore();
  @override
  void write(String data) {
    if (tuiForeground()) {
      inner.write(data);
    } else {
      lost();
    }
  }
}
