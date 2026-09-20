import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:keybay/keybay.dart';

import 'terminal.dart';
import 'lifetime.dart';

// Keep the CLI's bounded readers aligned with the public store contract.
const int maxSecretInputBytes = KeybayLimits.recordValueBytes;

final class SecretInputException implements Exception {
  const SecretInputException(
    this.message, {
    this.interactionUnavailable = false,
  });

  final String message;
  final bool interactionUnavailable;

  @override
  String toString() => message;
}

abstract interface class TerminalControl {
  bool get hasTerminal;
  bool get isForeground;
  bool get echoMode;
  set echoMode(bool value);
}

final class SecretInputReader {
  SecretInputReader({
    required this.input,
    required this.terminal,
    required this.stderr,
    this.managePosixSignals = false,
    required this.lifetime,
  }) : _nativeInput = false;

  SecretInputReader._system({
    required Stdin stdin,
    required this.stderr,
    required this.lifetime,
  }) : input = stdin,
       terminal = _StdinTerminalControl(stdin),
       managePosixSignals = true,
       _nativeInput = true;

  factory SecretInputReader.system({
    required Stdin stdin,
    required StringSink stderr,
    required CommandLifetime lifetime,
  }) => SecretInputReader._system(
    stdin: stdin,
    stderr: stderr,
    lifetime: lifetime,
  );

  final bool _nativeInput;
  final Stream<List<int>> input;
  final TerminalControl terminal;
  final StringSink stderr;
  final bool managePosixSignals;
  final CommandLifetime lifetime;

  /// Validate the channel before opening Keybay, and again before input.
  void authorize({required bool fromStdin}) {
    lifetime.check();
    if (fromStdin) {
      if (terminal.hasTerminal) {
        throw const SecretInputException(
          '--stdin expects piped input but stdin is a terminal; drop --stdin to use hidden input',
        );
      }
    } else if (!terminal.hasTerminal || !terminal.isForeground) {
      throw const SecretInputException(
        'interactive set requires its controlling foreground TTY; use --stdin for a value pipe',
        interactionUnavailable: true,
      );
    }
  }

  Future<Uint8List> read({required String key, required bool fromStdin}) async {
    authorize(fromStdin: fromStdin);
    if (fromStdin) {
      final bytes = await _readInput(
        input,
        maxSecretInputBytes + 2,
        lifetime: lifetime,
      );
      try {
        lifetime.check();
        return decodeSecretBytes(bytes);
      } finally {
        _clear(bytes);
      }
    }
    if (_nativeInput) {
      return _readControllingTerminal(
        prompt: 'Value for $key (input hidden): ',
        decode: (bytes) => decodeSecretBytes(bytes, stripEnding: false),
        maximumBytes: maxSecretInputBytes,
      );
    }
    return _readHidden(
      input: input,
      terminal: terminal,
      prompt: 'Value for $key (input hidden): ',
      write: stderr.write,
      writeNewline: stderr.writeln,
      decode: (bytes) => decodeSecretBytes(bytes, stripEnding: false),
      maximumBytes: maxSecretInputBytes,
    );
  }

  /// Reads one passphrase from the process's controlling terminal.
  ///
  /// Process stdin is never consumed. This remains true when stdin is the
  /// value pipe for `set --stdin` or is inherited by a future child of `run`.
  Future<Uint8List> readPassphrase({String? summary}) =>
      _readControllingTerminal(
        summary: summary,
        prompt: 'Keybay passphrase: ',
        decode: (bytes) => decodePassphraseBytes(bytes, stripEnding: false),
        maximumBytes: maxPassphraseInputBytes,
      );

  Future<Uint8List> _readControllingTerminal({
    String? summary,
    required String prompt,
    required Uint8List Function(List<int>) decode,
    required int maximumBytes,
  }) async {
    final attachment = _ControllingTerminalAttachment.open();
    Uint8List? result;
    try {
      lifetime.check();
      // Approval and prompt use the same attachment, never redirected stderr.
      if (summary != null) attachment.write(summary);
      result = await _readHidden(
        input: attachment.input(lifetime),
        terminal: attachment.terminal,
        prompt: prompt,
        write: attachment.write,
        writeNewline: attachment.writeNewline,
        decode: decode,
        maximumBytes: maximumBytes,
        bracketedPaste: attachment.setBracketedPaste,
      );
    } finally {
      try {
        attachment.close();
      } on Object {
        if (result != null) _clear(result);
        rethrow;
      }
    }
    return result;
  }

  Future<Uint8List> _readHidden({
    required Stream<List<int>> input,
    required TerminalControl terminal,
    required String prompt,
    required void Function(Object?) write,
    required void Function([Object?]) writeNewline,
    required Uint8List Function(List<int>) decode,
    required int maximumBytes,
    void Function(bool)? bracketedPaste,
  }) async {
    if (!terminal.hasTerminal || !terminal.isForeground) {
      throw const SecretInputException(
        'hidden input requires ownership of the foreground terminal',
        interactionUnavailable: true,
      );
    }

    final signalGuard = managePosixSignals
        ? _IgnoredSignalGuard([
            ProcessSignal.sigquit.signalNumber,
            ProcessSignal.sigtstp.signalNumber,
            _sigTtin,
            _sigTtou,
          ])
        : null;
    void Function()? restore;
    Uint8List? result;
    try {
      signalGuard?.start();
      if (terminal is _FileDescriptorTerminalControl) {
        restore = terminal.enterHiddenMode();
      } else {
        final previousEcho = terminal.echoMode;
        restore = () => terminal.echoMode = previousEcho;
        terminal.echoMode = false;
      }
      bracketedPaste?.call(true);
      write(prompt);
      final bytes = await _readHiddenInput(input, maximumBytes, lifetime);
      try {
        lifetime.check();
        if (!terminal.isForeground) {
          throw const SecretInputException(
            'the controlling terminal lost foreground ownership',
            interactionUnavailable: true,
          );
        }
        writeNewline();
        result = decode(bytes);
        return result;
      } finally {
        _clear(bytes);
      }
    } finally {
      // The native descriptor outlives the input stream, including EOF. Always
      // attempt mode restoration even if paste cleanup or cancellation fails.
      try {
        try {
          bracketedPaste?.call(false);
        } finally {
          try {
            restore?.call();
          } finally {
            signalGuard?.close();
          }
        }
      } on Object {
        if (result != null) _clear(result);
        rethrow;
      }
    }
  }
}

Uint8List decodeSecretBytes(List<int> bytes, {bool stripEnding = true}) {
  final valueLength = stripEnding
      ? _withoutProducerEnding(bytes)
      : bytes.length;
  if (valueLength > maxSecretInputBytes) {
    throw const SecretInputException(
      'secret input exceeds Keybay\'s 1 MiB record limit; store a '
      'credential rather than a blob',
    );
  }
  try {
    utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw const SecretInputException(
      'secret input is not valid UTF-8; provide a UTF-8 text value',
    );
  }
  if (bytes.contains(0)) {
    throw const SecretInputException(
      'secret input contains a NUL character; provide text without NUL',
    );
  }
  final length = valueLength;
  // An empty read is a failed producer (`op read … | keybay set --stdin` with
  // the producer printing nothing exits 0 without pipefail), or a bare Enter
  // at the prompt — not a credential. Storing it would silently replace a real
  // value with the empty string, so it fails loudly instead. A genuine 0-byte
  // value remains expressible through the bytes-first library API.
  if (length == 0) {
    throw const SecretInputException(
      'secret input is empty; refusing to store an empty value (a failed '
      'producer in a pipeline must not silently replace a stored secret)',
    );
  }
  return Uint8List(length)..setRange(0, length, bytes);
}

const int maxPassphraseInputBytes = 1024;

/// A bounded hidden editor. Enter submits; bracketed paste is literal UTF-8,
/// including CRLF and control bytes. Editing never creates a text/undo copy.
final class _HiddenInputBuffer {
  _HiddenInputBuffer(int maximum) : bytes = Uint8List(maximum);

  final Uint8List bytes;
  final List<int> _marker = [];
  var length = 0;
  var _paste = false;
  var _overflow = false;
  var complete = false;
  static const _start = [27, 91, 50, 48, 48, 126];
  static const _end = [27, 91, 50, 48, 49, 126];

  void add(List<int> chunk) {
    for (final byte in chunk) {
      if (complete) break;
      final marker = _paste ? _end : _start;
      if (_marker.isNotEmpty || byte == 27) {
        _marker.add(byte);
        while (_marker.isNotEmpty) {
          var matches = true;
          for (var i = 0; i < _marker.length; i++) {
            if (_marker[i] != marker[i]) {
              matches = false;
              break;
            }
          }
          if (matches) {
            if (_marker.length == marker.length) {
              _paste = !_paste;
              _marker.clear();
            }
            break;
          }
          _accept(_marker.removeAt(0));
          if (complete) break;
        }
      } else {
        _accept(byte);
      }
    }
  }

  void _accept(int byte) {
    if (!_paste) {
      switch (byte) {
        case 3: // Ctrl+C, handled here because paste must retain literal ETX.
          throw const CommandInterrupted(130);
        case 4: // Ctrl+D is EOF, including on an empty prompt.
        case 10:
        case 13:
          complete = true;
          return;
        case 8:
        case 127:
          if (length > 0 && !_overflow) {
            do {
              final removed = bytes[--length];
              bytes[length] = 0;
              if (removed & 0xc0 != 0x80) break;
            } while (length > 0);
          }
          return;
        case 21: // Ctrl+U starts a fresh draft, including after overflow.
          bytes.fillRange(0, length, 0);
          length = 0;
          _overflow = false;
          return;
        case 26: // Keep the existing no-suspend/no-quit prompt contract.
        case 28:
          return;
      }
    }
    if (length == bytes.length) {
      // Drain to submission without retaining more bytes. Returning mid-paste
      // would allow the remaining secret to arrive at the caller's shell.
      _overflow = true;
    } else {
      bytes[length++] = byte;
    }
  }

  Uint8List take() {
    if (_paste) {
      throw const SecretInputException('secret paste was interrupted');
    }
    if (!complete) {
      for (final byte in _marker) {
        _accept(byte);
      }
    }
    if (_overflow) {
      throw SecretInputException(
        bytes.length == maxSecretInputBytes
            ? "secret input exceeds Keybay's 1 MiB record limit; store a credential rather than a blob"
            : 'a Keybay passphrase must contain between 1 and 1024 UTF-8 bytes',
      );
    }
    return Uint8List.fromList(Uint8List.sublistView(bytes, 0, length));
  }

  void clear() {
    _clear(bytes);
    _marker.fillRange(0, _marker.length, 0);
    _marker.clear();
  }
}

Future<Uint8List> _readHiddenInput(
  Stream<List<int>> input,
  int maximum,
  CommandLifetime lifetime,
) async {
  final buffer = _HiddenInputBuffer(maximum);
  final done = Completer<void>();
  StreamSubscription<List<int>>? subscription;
  try {
    lifetime.check();
    subscription = input.listen(
      (chunk) {
        if (done.isCompleted) return;
        try {
          buffer.add(chunk);
          if (buffer.complete) done.complete();
        } on Object catch (error, stack) {
          done.completeError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await Future.any<void>([done.future, lifetime.cancelled]);
    lifetime.check();
    // Do not transfer a result until stream cleanup has succeeded.
    await subscription.cancel();
    subscription = null;
    return buffer.take();
  } finally {
    if (!done.isCompleted) done.complete();
    try {
      await subscription?.cancel();
    } finally {
      buffer.clear();
    }
  }
}

/// Applies the CLI's exact passphrase-to-bytes contract.
Uint8List decodePassphraseBytes(List<int> bytes, {bool stripEnding = true}) {
  final length = stripEnding ? _withoutProducerEnding(bytes) : bytes.length;
  if (length == 0 || length > maxPassphraseInputBytes) {
    throw const SecretInputException(
      'a Keybay passphrase must contain between 1 and 1024 UTF-8 bytes',
    );
  }
  final result = Uint8List(length)..setRange(0, length, bytes);
  try {
    utf8.decode(result, allowMalformed: false);
  } on FormatException {
    _clear(result);
    throw const SecretInputException(
      'the Keybay passphrase is not valid UTF-8',
    );
  }
  return result;
}

/// Own the buffer and subscription even on input errors/cancellation. Late
/// chunks cannot recreate an abandoned value. Only input is raced; SDK work is
/// always allowed to settle through the command's session owner.
Future<Uint8List> _readInput(
  Stream<List<int>> input,
  int maximum, {
  required CommandLifetime lifetime,
}) async {
  final buffer = Uint8List(maximum + 1);
  var length = 0;
  final done = Completer<void>();
  StreamSubscription<List<int>>? subscription;
  try {
    try {
      lifetime.check();
      subscription = input.listen(
        (chunk) {
          if (done.isCompleted) return;
          final wanted = chunk.length;
          final remaining = buffer.length - length;
          final count = wanted < remaining ? wanted : remaining;
          buffer.setRange(length, length + count, chunk);
          length += count;
          if (length == buffer.length) done.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      await Future.any<void>([done.future, lifetime.cancelled]);
      lifetime.check();
    } finally {
      if (!done.isCompleted) done.complete();
      await subscription?.cancel();
    }
    // Transfer only after every input cleanup succeeds.
    return Uint8List.fromList(Uint8List.sublistView(buffer, 0, length));
  } finally {
    _clear(buffer);
  }
}

int _withoutProducerEnding(List<int> bytes) {
  var length = bytes.length;
  if (length > 0 && bytes[length - 1] == 0x0a) {
    length--;
    if (length > 0 && bytes[length - 1] == 0x0d) length--;
  }
  return length;
}

final class _StdinTerminalControl implements TerminalControl {
  _StdinTerminalControl(this.stdin);

  final Stdin stdin;

  @override
  bool get hasTerminal => stdin.hasTerminal;

  @override
  bool get isForeground => terminalIsControllingForeground(0);

  @override
  bool get echoMode => stdin.echoMode;

  @override
  set echoMode(bool value) => stdin.echoMode = value;
}

typedef _NativeOpen = Int32 Function(Pointer<Utf8>, Int32);
typedef _DartOpen = int Function(Pointer<Utf8>, int);
typedef _NativeClose = Int32 Function(Int32);
typedef _DartClose = int Function(int);
typedef _NativeWrite = IntPtr Function(Int32, Pointer<Void>, IntPtr);
typedef _DartWrite = int Function(int, Pointer<Void>, int);
typedef _NativeGetTerminalAttributes = Int32 Function(Int32, Pointer<Void>);
typedef _DartGetTerminalAttributes = int Function(int, Pointer<Void>);
typedef _NativeSetTerminalAttributes =
    Int32 Function(Int32, Int32, Pointer<Void>);
typedef _DartSetTerminalAttributes = int Function(int, int, Pointer<Void>);

/// Owns the controlling terminal used for hidden prompts.
///
/// Descriptor zero is deliberately never replaced: it may be a secret-value
/// pipe for `set --stdin`, and Dart's stdin stream cannot safely survive a
/// temporary `dup2` to a different underlying file description.
final class _ControllingTerminalAttachment {
  _ControllingTerminalAttachment(this._terminalFd, _TerminalLayout layout)
    : terminal = _FileDescriptorTerminalControl(_terminalFd, layout);

  static final _DartOpen _open = _libc.lookupFunction<_NativeOpen, _DartOpen>(
    'open',
  );
  static final _DartClose _close = _libc
      .lookupFunction<_NativeClose, _DartClose>('close');
  static final _DartWrite _write = _libc
      .lookupFunction<_NativeWrite, _DartWrite>('write');

  static _ControllingTerminalAttachment open() {
    final layout = _qualifiedTerminalLayout();
    final path = '/dev/tty'.toNativeUtf8();
    late final int terminalFd;
    try {
      terminalFd = _open(
        path,
        2 | _closeOnExecFlag | (Platform.isMacOS ? 4 : 0x800),
      ); // O_RDWR | O_CLOEXEC | O_NONBLOCK
    } finally {
      calloc.free(path);
    }
    if (terminalFd < 0) {
      throw const SecretInputException(
        'passphrase input requires an available controlling terminal',
        interactionUnavailable: true,
      );
    }
    if (!terminalIsControllingForeground(terminalFd)) {
      _close(terminalFd);
      throw const SecretInputException(
        'passphrase input requires ownership of the foreground controlling terminal',
        interactionUnavailable: true,
      );
    }
    return _ControllingTerminalAttachment(terminalFd, layout);
  }

  static final _read = _libc
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  static final _errnoLocation = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );

  Stream<List<int>> input(CommandLifetime lifetime) {
    const capacity = 4096;
    Pointer<Uint8> buffer = nullptr;
    Timer? poll;
    var disposed = false;
    late final StreamController<List<int>> controller;
    void release() {
      if (disposed) return;
      disposed = true;
      poll?.cancel();
      if (buffer != nullptr) {
        buffer.asTypedList(capacity).fillRange(0, capacity, 0);
        calloc.free(buffer);
      }
    }

    void read() {
      if (disposed || controller.isPaused) return;
      var delay = Duration.zero;
      try {
        lifetime.check();
        if (!terminal.isForeground) {
          throw const SecretInputException(
            'the controlling terminal lost foreground ownership',
            interactionUnavailable: true,
          );
        }
        final count = _read(_terminalFd, buffer, capacity);
        if (count == 0) {
          unawaited(controller.close());
          return;
        }
        if (count > 0) {
          final chunk = Uint8List.fromList(buffer.asTypedList(count));
          try {
            // Synchronous delivery lets the consumer copy before erasure.
            controller.add(chunk);
          } finally {
            _clear(chunk);
          }
        } else {
          final error = _errnoLocation().value;
          if (error != 4 && error != (Platform.isMacOS ? 35 : 11)) {
            throw const SecretInputException(
              'the controlling terminal became unavailable',
              interactionUnavailable: true,
            );
          }
          delay = const Duration(milliseconds: 10);
        }
      } on Object catch (error, stack) {
        controller.addError(error, stack);
        unawaited(controller.close());
        return;
      }
      if (!disposed) poll = Timer(delay, read);
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        buffer = calloc<Uint8>(capacity);
        poll = Timer(Duration.zero, read);
      },
      onPause: () => poll?.cancel(),
      onResume: () => poll = Timer(Duration.zero, read),
      onCancel: release,
    );
    return controller.stream;
  }

  final int _terminalFd;
  final _FileDescriptorTerminalControl terminal;
  bool _closed = false;

  void setBracketedPaste(bool enabled) =>
      _writeString(enabled ? '\x1b[?2004h' : '\x1b[?2004l');

  void write(Object? value) => _writeString(value?.toString() ?? '');

  void writeNewline([Object? value]) {
    if (value != null) _writeString(value.toString());
    _writeString('\n');
  }

  void _writeString(String value) {
    if (!terminal.isForeground) {
      throw const SecretInputException(
        'the controlling terminal lost foreground ownership',
        interactionUnavailable: true,
      );
    }
    final bytes = utf8.encode(value);
    final buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      var offset = 0;
      while (offset < bytes.length) {
        final written = _write(
          _terminalFd,
          (buffer + offset).cast<Void>(),
          bytes.length - offset,
        );
        if (written <= 0) {
          throw const SecretInputException(
            'the controlling terminal became unavailable during passphrase input',
            interactionUnavailable: true,
          );
        }
        offset += written;
      }
    } finally {
      calloc.free(buffer);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_close(_terminalFd) != 0) {
      throw const SecretInputException(
        'controlling terminal cleanup failed',
        interactionUnavailable: true,
      );
    }
  }
}

final class _FileDescriptorTerminalControl implements TerminalControl {
  const _FileDescriptorTerminalControl(this.fd, this.layout);

  static final _DartGetTerminalAttributes _getAttributes = _libc
      .lookupFunction<_NativeGetTerminalAttributes, _DartGetTerminalAttributes>(
        'tcgetattr',
      );
  static final _DartSetTerminalAttributes _setAttributes = _libc
      .lookupFunction<_NativeSetTerminalAttributes, _DartSetTerminalAttributes>(
        'tcsetattr',
      );

  final int fd;
  final _TerminalLayout layout;

  static final _makeRaw = _libc
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('cfmakeraw');

  static final _flush = _libc
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'tcflush',
      );

  /// Return an exact restoration callback that owns the original termios.
  /// cfmakeraw removes canonical limits, CR translation and signal processing
  /// from pasted bytes. Output processing stays as the caller configured it.
  void Function() enterHiddenMode() {
    final size = layout == _TerminalLayout.darwin
        ? sizeOf<_DarwinTerminalAttributes>()
        : sizeOf<_LinuxTerminalAttributes>();
    final original = calloc<Uint8>(size);
    final hidden = calloc<Uint8>(size);
    try {
      _read(original.cast());
      hidden.asTypedList(size).setAll(0, original.asTypedList(size));
      _makeRaw(hidden.cast());
      switch (layout) {
        case _TerminalLayout.darwin:
          hidden.cast<_DarwinTerminalAttributes>().ref.outputFlags = original
              .cast<_DarwinTerminalAttributes>()
              .ref
              .outputFlags;
          // cfmakeraw on Darwin need not disable IXOFF/IXANY.
          hidden.cast<_DarwinTerminalAttributes>().ref.inputFlags &=
              ~(0x200 | 0x400 | 0x800);
        case _TerminalLayout.linuxGeneric:
          hidden.cast<_LinuxTerminalAttributes>().ref.outputFlags = original
              .cast<_LinuxTerminalAttributes>()
              .ref
              .outputFlags;
          hidden.cast<_LinuxTerminalAttributes>().ref.inputFlags &=
              ~(0x400 | 0x800 | 0x1000);
      }
      _write(hidden.cast());
    } on Object {
      calloc.free(original);
      rethrow;
    } finally {
      calloc.free(hidden);
    }
    return () {
      try {
        // Flush input separately: TCSAFLUSH also waits for output to drain,
        // which can deadlock a caller consuming stdout while the prompt uses
        // a different controlling terminal. Always attempt mode restoration.
        final flushed = _flush(fd, Platform.isMacOS ? 1 : 0); // TCIFLUSH
        final restored = _setAttributes(fd, 0, original.cast()); // TCSANOW
        if (restored != 0 || flushed != 0) {
          throw const SecretInputException(
            'controlling terminal mode restoration failed',
            interactionUnavailable: true,
          );
        }
      } finally {
        calloc.free(original);
      }
    };
  }

  @override
  bool get hasTerminal => terminalIsAttached(fd);

  @override
  bool get isForeground => terminalIsControllingForeground(fd);

  @override
  bool get echoMode {
    return switch (layout) {
      _TerminalLayout.darwin => _readDarwinEcho(),
      _TerminalLayout.linuxGeneric => _readLinuxEcho(),
    };
  }

  @override
  set echoMode(bool enabled) {
    switch (layout) {
      case _TerminalLayout.darwin:
        _writeDarwinEcho(enabled);
      case _TerminalLayout.linuxGeneric:
        _writeLinuxEcho(enabled);
    }
  }

  bool _readDarwinEcho() {
    final attributes = calloc<_DarwinTerminalAttributes>();
    try {
      _read(attributes.cast<Void>());
      return attributes.ref.localFlags & _echoFlag != 0;
    } finally {
      calloc.free(attributes);
    }
  }

  bool _readLinuxEcho() {
    final attributes = calloc<_LinuxTerminalAttributes>();
    try {
      _read(attributes.cast<Void>());
      return attributes.ref.localFlags & _echoFlag != 0;
    } finally {
      calloc.free(attributes);
    }
  }

  void _writeDarwinEcho(bool enabled) {
    final attributes = calloc<_DarwinTerminalAttributes>();
    try {
      _read(attributes.cast<Void>());
      attributes.ref.localFlags = _withEcho(attributes.ref.localFlags, enabled);
      _write(attributes.cast<Void>());
    } finally {
      calloc.free(attributes);
    }
  }

  void _writeLinuxEcho(bool enabled) {
    final attributes = calloc<_LinuxTerminalAttributes>();
    try {
      _read(attributes.cast<Void>());
      attributes.ref.localFlags = _withEcho(attributes.ref.localFlags, enabled);
      _write(attributes.cast<Void>());
    } finally {
      calloc.free(attributes);
    }
  }

  int _withEcho(int flags, bool enabled) =>
      enabled ? flags | _echoFlag : flags & ~_echoFlag;

  void _read(Pointer<Void> attributes) {
    if (_getAttributes(fd, attributes) != 0) {
      throw const SecretInputException(
        'the controlling terminal became unavailable during passphrase input',
        interactionUnavailable: true,
      );
    }
  }

  void _write(Pointer<Void> attributes) {
    if (_setAttributes(fd, _applyImmediately, attributes) != 0) {
      throw const SecretInputException(
        'the controlling terminal became unavailable during passphrase input',
        interactionUnavailable: true,
      );
    }
  }
}

const int _echoFlag = 0x00000008;
const int _applyImmediately = 0;
final int _closeOnExecFlag = Platform.isMacOS ? 0x01000000 : 0x00080000;

enum _TerminalLayout { darwin, linuxGeneric }

_TerminalLayout _qualifiedTerminalLayout() {
  final abi = Abi.current();
  if (abi == Abi.macosArm64 || abi == Abi.macosX64) {
    if (sizeOf<_DarwinTerminalAttributes>() == 72) {
      return _TerminalLayout.darwin;
    }
  } else if (abi == Abi.linuxArm64 || abi == Abi.linuxX64) {
    if (sizeOf<_LinuxTerminalAttributes>() == 60) {
      return _TerminalLayout.linuxGeneric;
    }
  }
  throw const SecretInputException(
    'passphrase input is unavailable on this unqualified terminal ABI',
    interactionUnavailable: true,
  );
}

/// Darwin's public `struct termios` layout on supported 64-bit macOS hosts.
final class _DarwinTerminalAttributes extends Struct {
  @UnsignedLong()
  external int inputFlags;

  @UnsignedLong()
  external int outputFlags;

  @UnsignedLong()
  external int controlFlags;

  @UnsignedLong()
  external int localFlags;

  @Array(20)
  external Array<Uint8> controlCharacters;

  @UnsignedLong()
  external int inputSpeed;

  @UnsignedLong()
  external int outputSpeed;
}

/// The generic `struct termios` layout qualified on Linux x64 and arm64.
final class _LinuxTerminalAttributes extends Struct {
  @Uint32()
  external int inputFlags;

  @Uint32()
  external int outputFlags;

  @Uint32()
  external int controlFlags;

  @Uint32()
  external int localFlags;

  @Uint8()
  external int lineDiscipline;

  @Array(32)
  external Array<Uint8> controlCharacters;

  @Uint32()
  external int inputSpeed;

  @Uint32()
  external int outputSpeed;
}

typedef _NativeSignal = Pointer<Void> Function(Int32, Pointer<Void>);
typedef _DartSignal = Pointer<Void> Function(int, Pointer<Void>);
final DynamicLibrary _libc = DynamicLibrary.process();

// POSIX job-control signal numbers are 21/22 on every supported host
// (Darwin, Linux/glibc, and Android/bionic).
const int _sigTtin = 21;
const int _sigTtou = 22;

/// Dart does not expose SIGQUIT or job-control signal streams on macOS.
/// Ignoring them only while the prompt owns the terminal is the fail-safe
/// temporary behavior: neither can strand echo disabled. The owner ratified
/// this austere contract instead of adding a native signal bridge solely for
/// the short hidden-input window (implementation plan §15).
final class _IgnoredSignalGuard {
  _IgnoredSignalGuard(this.signalNumbers);

  final List<int> signalNumbers;
  _DartSignal? _signal;
  final Map<int, Pointer<Void>> _previous = <int, Pointer<Void>>{};

  void start() {
    final signal = _libc.lookupFunction<_NativeSignal, _DartSignal>('signal');
    _signal = signal;
    for (final signalNumber in signalNumbers) {
      _previous[signalNumber] = signal(
        signalNumber,
        Pointer<Void>.fromAddress(1),
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

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
