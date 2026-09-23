import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'clipboard_contract.dart';
export 'clipboard_contract.dart';

/// Resolve one explicit write-only transport before reading any record. There
/// is no PATH lookup, shell, OSC 52 fallback, or clipboard read API.
Future<void> Function(String)? systemCopy() {
  if (Platform.isMacOS) {
    return (text) async {
      try {
        MacPasteboard().write(text);
      } on Object {
        throw const TuiCopyException();
      }
    };
  }
  if (!Platform.isLinux) return null;
  final env = Platform.environment;
  final wayland = (env['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
  final executable = wayland ? '/usr/bin/wl-copy' : '/usr/bin/xclip';
  if ((!wayland &&
          !RegExp(r'^:[0-9]+(?:\.[0-9]+)?$').hasMatch(env['DISPLAY'] ?? '')) ||
      !File(executable).existsSync()) {
    return null;
  }
  final arguments = wayland
      ? const ['--type', 'text/plain;charset=utf-8']
      : const ['-selection', 'clipboard', '-in', '-target', 'UTF8_STRING'];
  final environment = <String, String>{
    'LANG': 'C.UTF-8',
    for (final key in [
      'DISPLAY',
      'WAYLAND_DISPLAY',
      'XDG_RUNTIME_DIR',
      'XAUTHORITY',
      'HOME',
    ])
      if (env[key] case final value?) key: value,
  };
  return (text) async {
    Process? child;
    StreamSubscription<List<int>>? output;
    StreamSubscription<List<int>>? errors;
    final bytes = utf8.encode(text);
    try {
      child = await Process.start(
        executable,
        arguments,
        environment: environment,
        includeParentEnvironment: false,
      );
      output = child.stdout.listen((_) {});
      errors = child.stderr.listen((_) {});
      final process = child;
      await (() async {
        process.stdin.add(bytes);
        await process.stdin.close();
        if (await process.exitCode != 0) throw const TuiCopyException();
      })().timeout(const Duration(seconds: 3));
    } on Object {
      child?.kill(ProcessSignal.sigkill);
      throw const TuiCopyException();
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      await output?.cancel();
      await errors?.cancel();
    }
  };
}

/// `NSPasteboardContentsCurrentHostOnly`: no Continuity/Universal Clipboard.
const int _currentHostOnly = 1;

/// The nspasteboard.org markers asking clipboard managers not to show or
/// record an item. They are conventions each manager chooses to honor.
const List<String> _sensitiveMarkers = [
  'org.nspasteboard.ConcealedType',
  'org.nspasteboard.TransientType',
];

/// AppKit's typed string API avoids pbcopy's RTF/EPS type inference. Temporary
/// native UTF-8 buffers are cleared, and an autorelease pool scopes NSStrings.
/// The optional named board is only for isolated native qualification.
final class MacPasteboard {
  MacPasteboard() {
    DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');
  }
  static final _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
  static final _class = _objc
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)
      >('objc_getClass');
  static final _selector = _objc
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)
      >('sel_registerName');
  static final _send = _objc
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  static final _sendArg = _objc
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  static final _set = _objc
      .lookupFunction<
        Int8 Function(
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
          Pointer<Void>,
        ),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');
  static final _prepare = _objc
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Pointer<Void>, UintPtr),
        int Function(Pointer<Void>, Pointer<Void>, int)
      >('objc_msgSend');
  static final _void = _objc
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>),
        void Function(Pointer<Void>, Pointer<Void>)
      >('objc_msgSend');

  Pointer<Void> _name(
    String value,
    Pointer<Void> Function(Pointer<Utf8>) call,
  ) {
    final bytes = value.toNativeUtf8();
    try {
      return call(bytes);
    } finally {
      calloc.free(bytes);
    }
  }

  Pointer<Void> _sel(String value) => _name(value, _selector);
  Pointer<Void> _cls(String value) => _name(value, _class);
  Pointer<Void> _string(String value) {
    final bytes = value.toNativeUtf8();
    final length = bytes.length + 1;
    try {
      return _sendArg(
        _cls('NSString'),
        _sel('stringWithUTF8String:'),
        bytes.cast(),
      );
    } finally {
      bytes.cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
      calloc.free(bytes);
    }
  }

  void write(String value, {String? boardName}) {
    if (value.contains('\u0000')) throw const TuiCopyException();
    final pool = _send(
      _send(_cls('NSAutoreleasePool'), _sel('alloc')),
      _sel('init'),
    );
    try {
      final board = boardName == null
          ? _send(_cls('NSPasteboard'), _sel('generalPasteboard'))
          : _sendArg(
              _cls('NSPasteboard'),
              _sel('pasteboardWithName:'),
              _string(boardName),
            );
      if (board == nullptr) throw const TuiCopyException();
      final text = _string(value);
      if (text == nullptr) throw const TuiCopyException();
      // Keep the value off other devices (Universal Clipboard) and mark it with
      // the nspasteboard.org concealed/transient conventions that clipboard
      // history tools honor. Markers precede the value, so a failure leaves no
      // unmarked secret on the board.
      _prepare(
        board,
        _sel('prepareForNewContentsWithOptions:'),
        _currentHostOnly,
      );
      final empty = _string('');
      for (final marker in _sensitiveMarkers) {
        if (_set(board, _sel('setString:forType:'), empty, _string(marker)) ==
            0) {
          throw const TuiCopyException();
        }
      }
      if (_set(
            board,
            _sel('setString:forType:'),
            text,
            _string('public.utf8-plain-text'),
          ) ==
          0) {
        throw const TuiCopyException();
      }
    } finally {
      _void(pool, _sel('drain'));
    }
  }
}
