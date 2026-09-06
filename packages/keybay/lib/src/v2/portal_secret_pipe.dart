/// Anonymous portal output with cancellable, nonblocking reads.
///
/// dart:io ReadPipe uses a blocking file read whose cancellation waits for the
/// provider to write or close. A cancelled provider can retain its descriptor.
/// Polling this bounded nonblocking descriptor avoids an immortal I/O request.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

final class PortalSecretPipe {
  PortalSecretPipe._(this._readFd, this.output, this._buffer);

  factory PortalSecretPipe() {
    if (!Platform.isLinux && !Platform.isMacOS) {
      throw const FileSystemException('Unsupported portal pipe host');
    }
    final descriptors = calloc<Int32>(2);
    var readFd = -1;
    var writeFd = -1;
    RandomAccessFile? output;
    try {
      final result = Platform.isLinux
          ? _pipe2(
              descriptors,
              0x80000,
            ) // O_CLOEXEC; only read end is nonblocking.
          : _pipe(descriptors);
      if (result != 0) throw const FileSystemException('Portal pipe failed');
      readFd = descriptors[0];
      writeFd = descriptors[1];
      for (final fd in [readFd, writeFd]) {
        if (_fcntl(fd, 2, 1) == -1) {
          // F_SETFD, FD_CLOEXEC.
          throw const FileSystemException('Portal pipe flags failed');
        }
      }
      final flags = _fcntl(readFd, 3, 0); // F_GETFL.
      if (flags == -1 ||
          _fcntl(readFd, 4, flags | (Platform.isLinux ? 0x800 : 0x4)) == -1) {
        throw const FileSystemException('Portal nonblocking read failed');
      }
      // These OS descriptor aliases open the already-owned anonymous pipe;
      // they create no filesystem node and contain no provider-selected path.
      final aliases = Platform.isLinux ? '/proc/self/fd' : '/dev/fd';
      output = File('$aliases/$writeFd').openSync(mode: FileMode.writeOnly);
      return PortalSecretPipe._(readFd, output, calloc<Uint8>(_capacity));
    } catch (_) {
      if (readFd >= 0) _close(readFd);
      output?.closeSync();
      rethrow;
    } finally {
      if (writeFd >= 0) _close(writeFd);
      calloc.free(descriptors);
    }
  }

  // One byte beyond the protocol bound distinguishes overflow from valid EOF.
  static const _capacity = 4097;
  int _readFd;
  final RandomAccessFile output;
  Pointer<Uint8>? _buffer;
  Future<void>? _writerClose;

  /// null means not ready, empty means EOF. Returned bytes are caller-owned.
  Uint8List? readAvailable() {
    final buffer = _buffer;
    if (buffer == null) throw const FileSystemException('Portal pipe closed');
    final count = _read(_readFd, buffer, _capacity);
    if (count < 0) {
      final error = _errno().value;
      if (error == 4 || error == (Platform.isLinux ? 11 : 35)) return null;
      throw const FileSystemException('Portal pipe read failed');
    }
    final bytes = buffer.asTypedList(_capacity);
    try {
      return Uint8List(count)..setRange(0, count, bytes);
    } finally {
      bytes.fillRange(0, _capacity, 0);
    }
  }

  Future<void> closeWriter() => _writerClose ??= output.close().then((_) {});

  void closeReader() {
    if (_readFd >= 0) {
      _close(_readFd);
      _readFd = -1;
    }
    final buffer = _buffer;
    _buffer = null;
    if (buffer != null) {
      buffer.asTypedList(_capacity).fillRange(0, _capacity, 0);
      calloc.free(buffer);
    }
  }
}

final _libc = DynamicLibrary.process();
final _pipe = _libc
    .lookupFunction<
      Int32 Function(Pointer<Int32>),
      int Function(Pointer<Int32>)
    >('pipe');
final _pipe2 = _libc
    .lookupFunction<
      Int32 Function(Pointer<Int32>, Int32),
      int Function(Pointer<Int32>, int)
    >('pipe2');
final _fcntl = _libc
    .lookupFunction<
      Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
      int Function(int, int, int)
    >('fcntl');
final _read = _libc
    .lookupFunction<
      IntPtr Function(Int32, Pointer<Uint8>, UintPtr),
      int Function(int, Pointer<Uint8>, int)
    >('read');
final _close = _libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
  'close',
);
final _errno = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isLinux ? '__errno_location' : '__error',
    );
