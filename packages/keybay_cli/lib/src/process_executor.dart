import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'failure.dart';
import 'process_hardening.dart';
import 'terminal.dart';

/// A launch request prepared before opening Keybay. No environment overlay
/// participates in executable selection, and execution never searches again.
final class PreparedCommand {
  PreparedCommand({required this.path, required List<String> arguments})
    : arguments = List.unmodifiable(arguments);
  final String path;
  final List<String> arguments;
}

abstract interface class CommandExecutor {
  PreparedCommand prepare({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
  });
  Future<int> execute({
    required PreparedCommand command,
    required Map<String, String> overlay,
  });
}

abstract interface class ExecveSystem {
  int execve({
    required String path,
    required List<String> arguments,
    required Map<String, String> overlay,
  });
  int get errno;
}

final class SystemCommandExecutor implements CommandExecutor {
  SystemCommandExecutor({required this.stderr, required this.workingDirectory});
  final StringSink stderr;
  final String workingDirectory;
  PosixCommandExecutor? _delegate;
  PosixCommandExecutor get _executor => _delegate ??= PosixCommandExecutor(
    system: NativeExecveSystem(),
    stderr: stderr,
    workingDirectory: workingDirectory,
  );

  @override
  PreparedCommand prepare({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
  }) => _executor.prepare(
    executable: executable,
    arguments: arguments,
    environment: environment,
  );

  @override
  Future<int> execute({
    required PreparedCommand command,
    required Map<String, String> overlay,
  }) => _executor.execute(command: command, overlay: overlay);
}

final class PosixCommandExecutor implements CommandExecutor {
  PosixCommandExecutor({
    required this.system,
    required this.stderr,
    required this.workingDirectory,
  });
  final ExecveSystem system;
  final StringSink stderr;
  final String workingDirectory;

  static final _access = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('access');

  @override
  PreparedCommand prepare({
    required String executable,
    required List<String> arguments,
    required Map<String, String> environment,
  }) {
    if (!Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError('POSIX launch required');
    }
    var unusable = false;
    final path = environment['PATH'];
    final candidates = executable.contains('/')
        ? [executable]
        : [
            if (path != null)
              for (final directory in path.split(':'))
                directory.isEmpty ? executable : '$directory/$executable',
          ];
    for (final candidate in candidates) {
      final absolute = candidate.startsWith('/')
          ? candidate
          : '$workingDirectory/$candidate';
      try {
        final canonical = File(absolute).resolveSymbolicLinksSync();
        if (FileStat.statSync(canonical).type != FileSystemEntityType.file) {
          unusable = true;
          continue;
        }
        final nativePath = canonical.toNativeUtf8();
        try {
          if (_access(nativePath, 1 /* X_OK */) != 0) {
            unusable = true;
            continue;
          }
        } finally {
          malloc.free(nativePath);
        }
        return PreparedCommand(
          path: canonical,
          arguments: [executable, ...arguments],
        );
      } on FileSystemException catch (error) {
        // Missing/dangling paths are distinct from inaccessible existing ones.
        final code = error.osError?.errorCode;
        if (code != 2 && code != 20) unusable = true;
      }
    }
    throw CliFailure(
      exitCode: unusable ? 126 : 127,
      lines: [
        unusable
            ? 'error: command is not executable: ${terminalQuoted(executable)}'
            : 'error: command not found: ${terminalQuoted(executable)}',
        'Check the inherited PATH or use an executable absolute command path.',
      ],
    );
  }

  @override
  Future<int> execute({
    required PreparedCommand command,
    required Map<String, String> overlay,
  }) async {
    final result = system.execve(
      path: command.path,
      arguments: command.arguments,
      overlay: overlay,
    );
    if (result != -1) {
      stderr.writeln('error: execve returned unexpectedly; report this bug.');
      return 1;
    }
    // Resolution succeeded earlier. A disappeared/replaced target, missing
    // interpreter or bad format is now an invocation failure, never a retry.
    stderr.writeln(
      'error: command is not executable: ${terminalQuoted(command.path)}',
    );
    stderr.writeln(
      'Check the command format and interpreter (errno ${system.errno}).',
    );
    return 126;
  }
}

typedef _NativeExecve =
    Int32 Function(
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
    );
typedef _DartExecve =
    int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>);
typedef _NativeErrnoLocation = Pointer<Int32> Function();
typedef _DartErrnoLocation = Pointer<Int32> Function();
typedef _NativeSignal = Pointer<Void> Function(Int32, Pointer<Void>);
typedef _DartSignal = Pointer<Void> Function(int, Pointer<Void>);
typedef _NativeSigmask = Int32 Function(Int32, Pointer<Void>, Pointer<Void>);
typedef _DartSigmask = int Function(int, Pointer<Void>, Pointer<Void>);
typedef _NSGetEnviron = Pointer<Pointer<Pointer<Utf8>>> Function();

// Signal state the Dart VM alters for its own use, undone at the exec boundary
// so the child starts the way a shell would start it. Verified with a C probe:
// the VM leaves SIGPIPE ignored and SIGTTOU blocked on the calling thread, and
// both an ignored disposition and the thread's mask survive execve.
const int _sigpipe = 13; // same value on macOS and Linux
final int _sigSetmask = Platform.isMacOS ? 3 : 2; // SIG_SETMASK
// At least sizeof(sigset_t) everywhere keybay runs (Linux 128, macOS 4); a
// zero-filled buffer is the empty set on both, so no sigemptyset binding.
const int _sigsetBytes = 128;
final Pointer<Void> _sigDfl = Pointer<Void>.fromAddress(0); // SIG_DFL

final class NativeExecveSystem implements ExecveSystem {
  NativeExecveSystem() {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError('keybay run supports macOS and Linux only');
    }
    final library = DynamicLibrary.process();
    _execve = library.lookupFunction<_NativeExecve, _DartExecve>('execve');
    final errnoSymbol = Platform.isMacOS ? '__error' : '__errno_location';
    _errnoLocation = library
        .lookupFunction<_NativeErrnoLocation, _DartErrnoLocation>(errnoSymbol);
    _signal = library.lookupFunction<_NativeSignal, _DartSignal>('signal');
    _pthreadSigmask = library.lookupFunction<_NativeSigmask, _DartSigmask>(
      'pthread_sigmask',
    );
    // The raw `char **environ`. macOS dylibs cannot import the symbol
    // directly; _NSGetEnviron() is Apple's documented accessor. Linux exports
    // it as a plain data symbol.
    if (Platform.isMacOS) {
      final nsGetEnviron = library.lookupFunction<_NSGetEnviron, _NSGetEnviron>(
        '_NSGetEnviron',
      );
      _environ = () => nsGetEnviron().value;
    } else {
      final environSymbol = library.lookup<Pointer<Pointer<Utf8>>>('environ');
      _environ = () => environSymbol.value;
    }
  }

  late final _DartExecve _execve;
  late final _DartErrnoLocation _errnoLocation;
  late final _DartSignal _signal;
  late final _DartSigmask _pthreadSigmask;
  late final Pointer<Pointer<Utf8>> Function() _environ;
  int _lastErrno = 0;

  @override
  int get errno => _lastErrno;

  @override
  int execve({
    required String path,
    required List<String> arguments,
    required Map<String, String> overlay,
  }) {
    _validateNativeStrings(path, arguments, overlay);

    final allocatedStrings = <_NativeString>[];
    final pathPointer = _allocateString(path, allocatedStrings);
    final argumentPointers = _allocateStrings(arguments, allocatedStrings);
    final environmentPointers = _buildEnvironmentPointers(
      overlay,
      allocatedStrings,
    );
    // Hand the child shell-default signal state:
    // - SIGPIPE back to SIG_DFL, so a pipeline member dies silently on a
    //   closed pipe instead of surfacing EPIPE errors it never expects — the
    //   same reset CPython's subprocess performs for the dispositions it
    //   ignores. (A parent that deliberately ignored SIGPIPE before invoking
    //   keybay is indistinguishable from the VM's own ignore; shell-default
    //   fidelity wins that tie.)
    // - An empty signal mask via the calling thread (execve keeps that
    //   thread's mask). Neither call can fail with these constant arguments.
    final emptyMask = calloc<Uint8>(_sigsetBytes);
    final previousMask = calloc<Uint8>(_sigsetBytes);
    final previousSigpipe = _signal(_sigpipe, _sigDfl);
    _pthreadSigmask(_sigSetmask, emptyMask.cast(), previousMask.cast());
    // The program gets the caller's core-file limit; Keybay's zero limit is
    // process hardening, not child policy. execve restores dumpability.
    ProcessHardening.restoreForExec();
    try {
      final result = _execve(
        pathPointer,
        argumentPointers,
        environmentPointers,
      );
      // Read errno before the finally block below: its restore calls run on
      // this thread first and must not clobber the exec failure code.
      _lastErrno = _errnoLocation().value;
      return result;
    } finally {
      // A successful exec replaces this process image and never reaches here.
      // On failure, put the VM's signal state back first — the CLI still has
      // diagnostics to write and must not die of its own SIGPIPE — then
      // overwrite every native staging copy before releasing it; the
      // unavoidable Dart heap copies remain documented by SR-7. Inherited
      // environ entry pointers are libc's memory holding only parent values:
      // neither scrubbed nor freed.
      ProcessHardening.reapplyAfterFailedExec();
      _pthreadSigmask(_sigSetmask, previousMask.cast(), nullptr);
      _signal(_sigpipe, previousSigpipe);
      calloc
        ..free(emptyMask)
        ..free(previousMask);
      for (final allocation in allocatedStrings) {
        try {
          allocation.pointer
              .cast<Uint8>()
              .asTypedList(allocation.byteLength + 1)
              .fillRange(0, allocation.byteLength + 1, 0);
        } finally {
          malloc.free(allocation.pointer);
        }
      }
      calloc
        ..free(argumentPointers)
        ..free(environmentPointers);
    }
  }

  /// The child's envp: every raw `environ` entry whose name the manifest does
  /// not overlay passes through as its original pointer — byte-exact,
  /// including values `Platform.environment` cannot represent (it silently
  /// drops entries whose value is not valid UTF-8; verified) — followed by a
  /// freshly encoded `NAME=value` per overlay entry.
  Pointer<Pointer<Utf8>> _buildEnvironmentPointers(
    Map<String, String> overlay,
    List<_NativeString> allocatedStrings,
  ) {
    final overlayNames = <Uint8List>[
      for (final name in overlay.keys) utf8.encode(name),
    ];
    final inherited = <Pointer<Utf8>>[];
    final environ = _environ();
    if (environ != nullptr) {
      for (var index = 0; environ[index] != nullptr; index++) {
        final entry = environ[index];
        final raw = entry.cast<Uint8>();
        var length = 0;
        while (raw[length] != 0) {
          length++;
        }
        if (!overlayShadowsEnvEntry(raw.asTypedList(length), overlayNames)) {
          inherited.add(entry);
        }
      }
    }
    final pointers = calloc<Pointer<Utf8>>(
      inherited.length + overlay.length + 1,
    );
    var index = 0;
    for (final entry in inherited) {
      pointers[index++] = entry;
    }
    for (final entry in overlay.entries) {
      pointers[index++] = _allocateString(
        '${entry.key}=${entry.value}',
        allocatedStrings,
      );
    }
    pointers[index] = nullptr;
    return pointers;
  }
}

/// Whether a raw `environ` entry (the bytes of `NAME=VALUE`, no trailing NUL)
/// names a variable in [overlayNames] (each the UTF-8 bytes of one overlay
/// name). Byte-level on purpose: inherited entries never round-trip through
/// Dart strings. An entry without `=` can never match — overlay names cannot
/// contain `=` — so a parent's malformed entry passes through untouched.
bool overlayShadowsEnvEntry(Uint8List entry, List<Uint8List> overlayNames) {
  var nameLength = 0;
  while (nameLength < entry.length && entry[nameLength] != 0x3d /* '=' */ ) {
    nameLength++;
  }
  if (nameLength == entry.length) {
    return false;
  }
  for (final name in overlayNames) {
    if (name.length != nameLength) {
      continue;
    }
    var matches = true;
    for (var index = 0; index < nameLength; index++) {
      if (entry[index] != name[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}

Pointer<Pointer<Utf8>> _allocateStrings(
  List<String> values,
  List<_NativeString> allocatedStrings,
) {
  final pointers = calloc<Pointer<Utf8>>(values.length + 1);
  for (var index = 0; index < values.length; index++) {
    final pointer = _allocateString(values[index], allocatedStrings);
    pointers[index] = pointer;
  }
  pointers[values.length] = nullptr;
  return pointers;
}

Pointer<Utf8> _allocateString(
  String value,
  List<_NativeString> allocatedStrings,
) {
  final pointer = value.toNativeUtf8(allocator: malloc);
  allocatedStrings.add(_NativeString(pointer, pointer.length));
  return pointer;
}

final class _NativeString {
  const _NativeString(this.pointer, this.byteLength);

  final Pointer<Utf8> pointer;
  final int byteLength;
}

void _validateNativeStrings(
  String path,
  List<String> arguments,
  Map<String, String> overlay,
) {
  if (path.contains('\u0000')) {
    throw StateError('command path contains NUL');
  }
  for (final argument in arguments) {
    if (argument.contains('\u0000')) {
      throw StateError('command argument contains NUL');
    }
  }
  // Only the overlay is materialized as new envp strings; inherited environ
  // entries are already valid environ bytes by construction.
  for (final entry in overlay.entries) {
    if (entry.key.contains('=') ||
        entry.key.contains('\u0000') ||
        entry.value.contains('\u0000')) {
      throw StateError(
        'child environment overlay is not representable as envp',
      );
    }
  }
}
