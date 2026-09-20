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
  });

  factory SecretInputReader.system({
    required Stdin stdin,
    required StringSink stderr,
    required CommandLifetime lifetime,
  }) => SecretInputReader(
    input: stdin,
    terminal: _StdinTerminalControl(stdin),
    stderr: stderr,
    managePosixSignals: true,
    lifetime: lifetime,
  );

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
    return _readHidden(
      input: input,
      terminal: terminal,
      prompt: 'Value for $key (input hidden): ',
      write: stderr.write,
      writeNewline: stderr.writeln,
      decode: decodeSecretBytes,
      maximumLineBytes: maxSecretInputBytes + 2,
    );
  }

  /// Reads one passphrase from the process's controlling terminal.
  ///
  /// Process stdin is never consumed. This remains true when stdin is the
  /// value pipe for `set --stdin` or is inherited by a future child of `run`.
  Future<Uint8List> readPassphrase({String? summary}) async {
    final attachment = _ControllingTerminalAttachment.open();
    Uint8List? result;
    try {
      lifetime.check();
      // Approval and prompt use the same attachment, never redirected stderr.
      if (summary != null) attachment.write(summary);
      result = await _readHidden(
        input: attachment.input(lifetime),
        terminal: attachment.terminal,
        prompt: 'Keybay passphrase: ',
        write: attachment.write,
        writeNewline: attachment.writeNewline,
        decode: decodePassphraseBytes,
        maximumLineBytes: maxPassphraseInputBytes + 2,
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
    required int maximumLineBytes,
  }) async {
    if (!terminal.hasTerminal || !terminal.isForeground) {
      throw const SecretInputException(
        'hidden input requires ownership of the foreground terminal',
        interactionUnavailable: true,
      );
    }

    final previousEchoMode = terminal.echoMode;
    final signalGuard = managePosixSignals
        ? _IgnoredSignalGuard([
            ProcessSignal.sigquit.signalNumber,
            ProcessSignal.sigtstp.signalNumber,
            _sigTtin,
            _sigTtou,
          ])
        : null;
    var restorationAttempted = false;
    void restoreEcho() {
      restorationAttempted = true;
      terminal.echoMode = previousEchoMode;
    }

    try {
      // Install the guards while echo is still in its original state. If a
      // signal lands anywhere after echo is disabled, a handler is already in
      // place to restore it (or the fail-safe disposition is already active).
      signalGuard?.start();
      terminal.echoMode = false;
      write(prompt);
      final bytes = await _readInput(
        input,
        maximumLineBytes,
        oneLine: true,
        lifetime: lifetime,
        beforeCancel: () {
          try {
            if (!terminal.isForeground) {
              throw const SecretInputException(
                'the controlling terminal lost foreground ownership',
                interactionUnavailable: true,
              );
            }
          } finally {
            // Dart closes stdin's descriptor when its subscription is
            // cancelled. Restore while it is still owned and usable.
            restoreEcho();
          }
        },
      );
      try {
        lifetime.check();
        writeNewline();
        return decode(bytes);
      } finally {
        _clear(bytes);
      }
    } finally {
      // Every cleanup action must run even if an earlier one fails. A terminal
      // can disappear while input is pending; a failed echo restoration must
      // not leave the temporary signal dispositions or stdin subscription
      // installed for the remainder of the process.
      try {
        if (!restorationAttempted) restoreEcho();
      } finally {
        signalGuard?.close();
      }
    }
  }
}

Uint8List decodeSecretBytes(List<int> bytes) {
  final valueLength = _withoutProducerEnding(bytes);
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
  var length = bytes.length;
  if (length > 0 && bytes[length - 1] == 0x0a) {
    length--;
    if (length > 0 && bytes[length - 1] == 0x0d) length--;
  }
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

/// Applies the CLI's exact passphrase-to-bytes contract.
Uint8List decodePassphraseBytes(List<int> bytes) {
  var length = bytes.length;
  if (length > 0 && bytes[length - 1] == 0x0a) {
    length--;
    if (length > 0 && bytes[length - 1] == 0x0d) length--;
  }
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
  bool oneLine = false,
  required CommandLifetime lifetime,
  void Function()? beforeCancel,
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
          final newline = oneLine ? chunk.indexOf(0x0a) : -1;
          final wanted = newline < 0 ? chunk.length : newline + 1;
          final remaining = buffer.length - length;
          final count = wanted < remaining ? wanted : remaining;
          buffer.setRange(length, length + count, chunk);
          length += count;
          if (newline >= 0 || length == buffer.length) done.complete();
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
      try {
        beforeCancel?.call();
      } finally {
        await subscription?.cancel();
      }
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

/// Owns the controlling terminal used for passphrase prompts.
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

  Stream<List<int>> input(CommandLifetime lifetime) async* {
    final buffer = calloc<Uint8>(maxPassphraseInputBytes + 3);
    try {
      while (true) {
        lifetime.check();
        if (!terminal.isForeground) {
          throw const SecretInputException(
            'the controlling terminal lost foreground ownership',
            interactionUnavailable: true,
          );
        }
        final count = _read(_terminalFd, buffer, maxPassphraseInputBytes + 3);
        if (count == 0) return;
        if (count > 0) {
          final chunk = Uint8List.fromList(buffer.asTypedList(count));
          try {
            yield chunk;
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
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    } finally {
      buffer
          .asTypedList(maxPassphraseInputBytes + 3)
          .fillRange(0, maxPassphraseInputBytes + 3, 0);
      calloc.free(buffer);
    }
  }

  final int _terminalFd;
  final TerminalControl terminal;
  bool _closed = false;

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
