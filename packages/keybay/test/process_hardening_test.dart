@Tags(['unit'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/process_hardening.dart';
import 'package:test/test.dart';

void main() {
  test(
    'hardenProcess disables core files and, on Linux, dumpability',
    () {
      // Start from a caller that allows core files and, on Linux, is dumpable;
      // a default limit of 0 would let every expectation pass even if nothing
      // were changed.
      final (original, hard) = _coreLimits();
      if (hard == 0) {
        markTestSkipped('the hard core-file limit is 0 here');
        return;
      }
      final caller = hard > 0 && hard < 1 << 20 ? hard : 1 << 20;
      _setSoftCoreLimit(caller);
      addTearDown(() => _setSoftCoreLimit(original));
      if (Platform.isLinux) {
        final dumpable = linuxDumpable!;
        addTearDown(() => _prctl(_prSetDumpable, dumpable, 0, 0, 0));
        expect(_prctl(_prSetDumpable, 1, 0, 0, 0), 0);
        expect(linuxDumpable, 1);
        // A child running as the same user reads a dumpable parent's /proc
        // entries; that read is the positive control for the one below.
        expect(_childReads('/proc/$pid/environ'), isTrue);
      }

      final result = Keybay.hardenProcess();

      expect(result.failed, isFalse, reason: '$result');
      expect(result.coreDumps.status, KeybayHardeningStatus.applied);
      expect(softCoreLimit, 0);
      expect(_coreLimits().$2, hard, reason: 'the hard limit is unchanged');
      if (Platform.isLinux) {
        expect(linuxDumpable, 0);
        expect(result.debuggerAttach.status, KeybayHardeningStatus.applied);
        expect(_childReads('/proc/$pid/environ'), isFalse);
        // Opening mem needs attach rights, which Yama may already refuse a
        // child, so only the denial is asserted.
        expect(_childOpens('/proc/$pid/mem'), isFalse);
      } else {
        expect(
          result.debuggerAttach.status,
          KeybayHardeningStatus.notAttempted,
        );
        expect(result.debuggerAttach.detail, contains('PT_DENY_ATTACH'));
      }

      // Repeating the call is harmless and reports the same policy.
      final again = Keybay.hardenProcess();
      expect(again.coreDumps.status, result.coreDumps.status);
      expect(again.debuggerAttach.status, result.debuggerAttach.status);
    },
    testOn: 'mac-os || linux',
  );

  test('the result reports Yama and X11 only on Linux', () {
    final result = Keybay.hardenProcess();
    if (Platform.isLinux) {
      expect(result.ptraceScope, linuxPtraceScope());
      expect(
        result.ptraceUnrestricted,
        result.ptraceScope == null || result.ptraceScope == 0,
      );
      expect(result.x11Session, isX11Session(Platform.environment));
    } else {
      expect(result.ptraceScope, isNull);
      expect(result.ptraceUnrestricted, isFalse);
      expect(result.x11Session, isFalse);
    }
    expect(result.toString(), contains('coreDumps: '));
  });

  test('Yama ptrace_scope parses the four defined scopes only', () {
    for (final (text, scope) in [
      ('0\n', 0),
      ('1\n', 1),
      ('2', 2),
      ('3\n', 3),
      ('4\n', null),
      ('-1\n', null),
      ('', null),
      ('restricted\n', null),
    ]) {
      expect(linuxPtraceScope(read: () => text), scope, reason: text);
    }
    expect(
      linuxPtraceScope(read: () => throw const FileSystemException('absent')),
      isNull,
    );
  });

  test('TracerPid is read from /proc/self/status', () {
    for (final (text, tracer) in [
      ('Name:\tdart\nTracerPid:\t0\nUid:\t1000\n', 0),
      ('TracerPid:\t4242\n', 4242),
      ('Name:\tdart\n', null),
      ('TracerPid:\tnone\n', null),
    ]) {
      expect(linuxTracerPid(read: () => text), tracer, reason: text);
    }
    expect(
      linuxTracerPid(read: () => throw const FileSystemException('absent')),
      isNull,
    );
    if (Platform.isLinux) expect(linuxTracerPid(), 0);
  });

  test('an X11 session is XDG_SESSION_TYPE x11 or DISPLAY without Wayland', () {
    for (final (environment, x11) in <(Map<String, String>, bool)>[
      ({'XDG_SESSION_TYPE': 'x11'}, true),
      ({'XDG_SESSION_TYPE': 'x11', 'WAYLAND_DISPLAY': 'wayland-0'}, true),
      ({'DISPLAY': ':0'}, true),
      ({'XDG_SESSION_TYPE': 'wayland', 'DISPLAY': ':0'}, true),
      ({'DISPLAY': ':0', 'WAYLAND_DISPLAY': 'wayland-0'}, false),
      (
        {
          'XDG_SESSION_TYPE': 'wayland',
          'DISPLAY': ':0',
          'WAYLAND_DISPLAY': 'wayland-0',
        },
        false,
      ),
      ({'XDG_SESSION_TYPE': 'tty'}, false),
      ({'DISPLAY': ''}, false),
      ({}, false),
    ]) {
      expect(isX11Session(environment), x11, reason: '$environment');
    }
  });
}

/// Whether a child process running as this user can open [path].
bool _childOpens(String path) =>
    Process.runSync('/bin/sh', ['-c', 'exec 3<"\$1"', 'sh', path]).exitCode ==
    0;

/// Whether a child process running as this user can read [path].
bool _childReads(String path) =>
    Process.runSync('/bin/sh', [
      '-c',
      'head -c 1 "\$1" >/dev/null 2>&1',
      'sh',
      path,
    ]).exitCode ==
    0;

// RLIMIT_CORE is 4 on Darwin and Linux, and rlim_t is 64-bit on both.
final class _Rlimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

const _prSetDumpable = 4;

final _libc = DynamicLibrary.process();
final _getrlimit = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_Rlimit>),
      int Function(int, Pointer<_Rlimit>)
    >('getrlimit');
final _setrlimit = _libc
    .lookupFunction<
      Int32 Function(Int32, Pointer<_Rlimit>),
      int Function(int, Pointer<_Rlimit>)
    >('setrlimit');
final _prctl = _libc
    .lookupFunction<
      Int32 Function(
        Int32,
        VarArgs<(UnsignedLong, UnsignedLong, UnsignedLong, UnsignedLong)>,
      ),
      int Function(int, int, int, int, int)
    >('prctl');

(int, int) _coreLimits() {
  final limit = calloc<_Rlimit>();
  try {
    expect(_getrlimit(4, limit), 0);
    return (limit.ref.current, limit.ref.maximum);
  } finally {
    calloc.free(limit);
  }
}

void _setSoftCoreLimit(int soft) {
  final limit = calloc<_Rlimit>();
  try {
    expect(_getrlimit(4, limit), 0);
    limit.ref.current = soft;
    expect(_setrlimit(4, limit), 0);
  } finally {
    calloc.free(limit);
  }
}
