/// Fail-closed tracking for native-item scheme use on macOS.
///
/// A signed app can lose its Keychain Sharing entitlement between releases.
/// Without a durable, non-secret trace of prior native-item use, the resolver
/// would then select the encrypted-file scheme and present an empty-looking
/// store while the old Data Protection Keychain items remain OS-walled. This
/// file provides the smallest mechanism that makes that transition visible.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../backend.dart';
import '../errors.dart';
import '../ffi/posix_file.dart';

/// Records and verifies native-item use for one macOS store.
///
/// The marker contains only a version, scheme name, and base64-encoded access
/// group (signing metadata, not secret data). It is private and authenticated
/// by directory/file ownership assumptions, but it is not treated as a secret.
/// A conflicting or malformed marker fails closed.
final class MacOSSchemeGuard {
  MacOSSchemeGuard({
    required this.appId,
    required this.markerPath,
    this.accessGroup,
    SecureFileSystem fs = const SecureFileSystem(),
  }) : _fs = fs;

  final String appId;
  final String markerPath;
  final String? accessGroup;
  final SecureFileSystem _fs;

  String get _parentDir {
    final i = markerPath.lastIndexOf('/');
    return i <= 0 ? '.' : markerPath.substring(0, i);
  }

  String get _lockPath => '$markerPath.lock';

  Uint8List _expectedBytes(String group) => Uint8List.fromList(utf8.encode(
        'keybay-scheme-v1\nnativeItems\n${base64Url.encode(utf8.encode(group))}\n',
      ));

  Uint8List? _read() {
    if (!_fs.verifyPrivateDirSync(_parentDir)) return null;
    return _fs.readCappedSync(
      markerPath,
      maxBytes: 4096,
      requirePrivate: true,
    );
  }

  String _parseGroup(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const KeystoreOperationFailed(
        'macOS scheme marker is malformed; refusing to select a store',
      );
    }
    final lines = text.split('\n');
    if (lines.length != 4 ||
        lines[0] != 'keybay-scheme-v1' ||
        lines[1] != 'nativeItems' ||
        lines[2].isEmpty ||
        lines[3].isNotEmpty) {
      throw const KeystoreOperationFailed(
        'macOS scheme marker is malformed; refusing to select a store',
      );
    }
    try {
      final group = utf8.decode(base64Url.decode(lines[2]));
      if (group.isEmpty) throw const FormatException('empty access group');
      return group;
    } on FormatException {
      throw const KeystoreOperationFailed(
        'macOS scheme marker is malformed; refusing to select a store',
      );
    }
  }

  /// Refuses an encrypted-file fallback after any recorded native-item use.
  void verifyFileSelection() {
    final existing = _read();
    if (existing == null) return;
    _parseGroup(existing);
    throw MigrationRequired(
      appId: appId,
      from: StorageScheme.nativeItems,
      to: StorageScheme.encryptedFile,
    );
  }

  /// Verifies an existing marker agrees with the currently selected group.
  void verifyNativeSelection() {
    final expected = accessGroup;
    if (expected == null || expected.isEmpty) {
      throw StateError('native selection requires an access group');
    }
    final existing = _read();
    if (existing == null) return;
    if (_parseGroup(existing) != expected) {
      throw KeychainAccessGroupChanged(appId);
    }
  }

  /// Atomically records native selection before a persistent mutation.
  ///
  /// Recording first deliberately prefers a possible conservative false
  /// positive after a crash over writing a native secret without the trace that
  /// prevents a later silent downgrade. Once written, the marker is retained
  /// even after delete-all; clearing it is part of an explicit migration/reset.
  Future<void> recordNativeSelection() async {
    final expected = accessGroup;
    if (expected == null || expected.isEmpty) {
      throw StateError('native selection requires an access group');
    }
    _fs.ensurePrivateDirSync(_parentDir);
    await _fs.withExclusiveLock(
      _lockPath,
      timeout: const Duration(seconds: 10),
      body: () async {
        final existing = _read();
        if (existing == null) {
          _fs.writeAtomicSync(markerPath, _expectedBytes(expected));
          return;
        }
        if (_parseGroup(existing) != expected) {
          throw KeychainAccessGroupChanged(appId);
        }
      },
    );
  }
}

/// Adds scheme tracking to a native-item backend without changing its storage
/// behavior or capability reporting.
final class SchemeTrackingBackend implements AtomicDeleteAllBackend {
  SchemeTrackingBackend({
    required AtomicDeleteAllBackend backend,
    required Future<void> Function() recordNativeSelection,
  })  : _backend = backend,
        _recordNativeSelection = recordNativeSelection;

  final AtomicDeleteAllBackend _backend;
  final Future<void> Function() _recordNativeSelection;

  @override
  BackendCapabilities get capabilities => _backend.capabilities;

  @override
  Future<Uint8List?> read(String key) async {
    final value = await _backend.read(key);
    if (value != null) await _recordNativeSelection();
    return value;
  }

  @override
  Future<bool> contains(String key) async {
    final present = await _backend.contains(key);
    if (present) await _recordNativeSelection();
    return present;
  }

  @override
  Future<void> write(String key, Uint8List value, {String? label}) async {
    await _recordNativeSelection();
    await _backend.write(key, value, label: label);
  }

  @override
  Future<void> delete(String key) async {
    if (await _backend.contains(key)) await _recordNativeSelection();
    await _backend.delete(key);
  }

  @override
  Future<void> deleteAll() async {
    // A bulk delete cannot cheaply prove whether native items exist without
    // materializing every secret. Record conservatively before the mutation.
    await _recordNativeSelection();
    await _backend.deleteAll();
  }

  @override
  Future<Map<String, Uint8List>> readAll() async {
    final values = await _backend.readAll();
    if (values.isNotEmpty) await _recordNativeSelection();
    return values;
  }

  @override
  Future<BackendInfo> describe() => _backend.describe();
}
