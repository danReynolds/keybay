import 'dart:convert';
import 'dart:io';

import 'tui/appearance.dart';

/// A small, unencrypted preference file, readable before vault authentication.
final class FileAppearancePreference {
  FileAppearancePreference(this.file);
  final File file;

  static FileAppearancePreference? forCurrentUser() {
    final home = Platform.environment['HOME'];
    if (home == null || !home.startsWith('/')) return null;
    final config = Platform.environment['XDG_CONFIG_HOME'];
    final base = Platform.isMacOS
        ? '$home/Library/Application Support'
        : config != null && config.startsWith('/')
        ? config
        : '$home/.config';
    return FileAppearancePreference(File('$base/keybay/appearance.json'));
  }

  Future<TuiAppearance> read() async {
    RandomAccessFile? handle;
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return const TuiAppearance();
      }
      handle = await file.open();
      final bytes = await handle.read(1025);
      if (bytes.length > 1024) return const TuiAppearance();
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> || data['version'] != 1) {
        return const TuiAppearance();
      }
      return TuiAppearance(
        accent:
            TuiAccent.values
                .where((v) => v.name == data['accent'])
                .firstOrNull ??
            TuiAccent.green,
        contrast:
            TuiContrast.values
                .where((v) => v.name == data['contrast'])
                .firstOrNull ??
            TuiContrast.normal,
      );
    } on Object {
      return const TuiAppearance();
    } finally {
      try {
        await handle?.close();
      } on Object {
        /* Optional local state. */
      }
    }
  }

  Future<void> write(TuiAppearance appearance) async {
    final kind = await FileSystemEntity.type(file.path, followLinks: false);
    if (kind != FileSystemEntityType.file &&
        kind != FileSystemEntityType.notFound) {
      throw const FileSystemException('Appearance path is not a regular file');
    }
    await file.parent.create(recursive: true);
    final temporary = await file.parent.createTemp('.appearance-');
    try {
      final stage = File('${temporary.path}/preference');
      await stage.writeAsString(
        '${jsonEncode({'version': 1, 'accent': appearance.accent.name, 'contrast': appearance.contrast.name})}\n',
        flush: true,
      );
      await stage.rename(file.path);
    } finally {
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        // Cleanup failure must not misreport a successfully saved preference.
      }
    }
  }
}
