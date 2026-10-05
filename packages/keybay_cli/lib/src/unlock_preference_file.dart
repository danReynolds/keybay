import 'dart:convert';
import 'dart:io';

import 'tui/unlock_preference.dart';

/// Best-effort local UI state, deliberately separate from the encrypted vault.
final class FileUnlockPreference implements UnlockPreference {
  FileUnlockPreference(this.file);

  final File file;
  static final _methodId = RegExp(r'^[0-9a-f]{32}$');
  static const _maximumBytes = 256;

  static UnlockPreference? forCurrentUser() {
    final home = Platform.environment['HOME'];
    if (home == null || !home.startsWith('/')) return null;
    final state = Platform.environment['XDG_STATE_HOME'];
    final base = Platform.isMacOS
        ? '$home/Library/Application Support'
        : state != null && state.startsWith('/')
        ? state
        : '$home/.local/state';
    return FileUnlockPreference(File('$base/keybay/unlock-method.json'));
  }

  @override
  Future<String?> read() async {
    RandomAccessFile? handle;
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      handle = await file.open();
      final bytes = await handle.read(_maximumBytes + 1);
      if (bytes.length > _maximumBytes) return null;
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> || data['version'] != 1) return null;
      final id = data['methodId'];
      return id is String && _methodId.hasMatch(id) ? id : null;
    } on Object {
      return null;
    } finally {
      try {
        await handle?.close();
      } on Object {
        // Read/close failures have the same best-effort behavior.
      }
    }
  }

  @override
  Future<void> write(String methodId) async {
    if (!_methodId.hasMatch(methodId)) return;
    Directory? temporary;
    try {
      final kind = await FileSystemEntity.type(file.path, followLinks: false);
      if (kind != FileSystemEntityType.notFound &&
          kind != FileSystemEntityType.file) {
        return;
      }
      await file.parent.create(recursive: true);
      temporary = await file.parent.createTemp('.unlock-');
      final stage = File('${temporary.path}/preference');
      await stage.writeAsString(
        '${jsonEncode({'version': 1, 'methodId': methodId})}\n',
        flush: true,
      );
      await stage.rename(file.path);
    } on Object {
      // An unavailable preference directory must never make unlock fail.
    } finally {
      try {
        await temporary?.delete(recursive: true);
      } on Object {
        // The uniquely owned staging directory contains only this UI hint.
      }
    }
  }
}
