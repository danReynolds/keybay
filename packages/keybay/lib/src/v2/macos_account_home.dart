/// Trusted macOS account-home resolution for host-profile routing.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'store_files.dart';

const int _accountBufferBytes = 64 * 1024;

/// Returns the canonical home of the process's effective macOS account.
///
/// Environment variables and the current directory are deliberately ignored.
/// The fixed buffer bounds NSS output; an absent, malformed, or non-absolute
/// password-database record fails closed.
String resolveMacOSAccountHome() {
  if (!Platform.isMacOS) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }

  final record = calloc<_DarwinPasswd>();
  final result = calloc<Pointer<_DarwinPasswd>>()..value = nullptr;
  final buffer = calloc<Uint8>(_accountBufferBytes);
  try {
    final status = _getpwuidR(
      _geteuid(),
      record,
      buffer.cast<Utf8>(),
      _accountBufferBytes,
      result,
    );
    if (status != 0 || result.value != record) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    final directory = record.ref.directory;
    final offset = directory.address - buffer.address;
    if (directory == nullptr || offset < 0 || offset >= _accountBufferBytes) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    final bytes = directory.cast<Uint8>();
    var length = 0;
    while (offset + length < _accountBufferBytes && bytes[length] != 0) {
      length++;
    }
    if (length == 0 || offset + length >= _accountBufferBytes) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    final home = utf8.decode(bytes.asTypedList(length), allowMalformed: false);
    if (!home.startsWith('/') || home.length > 4096) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final canonical = Directory(home).resolveSymbolicLinksSync();
    if (!canonical.startsWith('/') || canonical.length > 4096) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    return canonical;
  } on StoreFilesFailure {
    rethrow;
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  } finally {
    calloc.free(buffer);
    calloc.free(result);
    calloc.free(record);
  }
}

final class _DarwinPasswd extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> password;

  @Uint32()
  external int userId;

  @Uint32()
  external int groupId;

  @Int64()
  external int changedAt;

  external Pointer<Utf8> userClass;
  external Pointer<Utf8> gecos;
  external Pointer<Utf8> directory;
  external Pointer<Utf8> shell;

  @Int64()
  external int expiresAt;
}

final DynamicLibrary _libc = DynamicLibrary.process();

final int Function() _geteuid = _libc
    .lookupFunction<Uint32 Function(), int Function()>('geteuid');

final int Function(
  int,
  Pointer<_DarwinPasswd>,
  Pointer<Utf8>,
  int,
  Pointer<Pointer<_DarwinPasswd>>,
)
_getpwuidR = _libc
    .lookupFunction<
      Int32 Function(
        Uint32,
        Pointer<_DarwinPasswd>,
        Pointer<Utf8>,
        IntPtr,
        Pointer<Pointer<_DarwinPasswd>>,
      ),
      int Function(
        int,
        Pointer<_DarwinPasswd>,
        Pointer<Utf8>,
        int,
        Pointer<Pointer<_DarwinPasswd>>,
      )
    >('getpwuid_r');
