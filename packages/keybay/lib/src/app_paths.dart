/// Derived per-app storage locations (see doc/design.md §9).
///
/// The container path is a pure function of the validated `appId` — no path
/// knob exists on the public API. `appId` is a single traversal-proof path
/// segment (enforced by `validateAppId`), so these joins cannot escape the
/// platform data directory.
library;

import 'dart:io';

import 'errors.dart';
import 'ffi/posix_file.dart';

/// The container file name inside the app's data directory.
const String containerFileName = 'secrets.enc';

/// Non-secret macOS trace that prevents a later loss of Keychain Sharing
/// entitlement from silently selecting an empty encrypted-file store.
const String macosSchemeMarkerFileName = '.scheme';

/// Derives the container file path for [appId] on this platform:
///
/// - macOS: `~/Library/Application Support/<appId>/secrets.enc`
/// - Linux: `${XDG_DATA_HOME:-~/.local/share}/<appId>/secrets.enc`
///   (a relative `XDG_DATA_HOME` is ignored, per the XDG Base Directory spec)
///
/// [appId] must already have passed `validateAppId`. [environment] is an
/// internal test seam; production callers use the process environment.
/// Throws [KeystoreUnreachable] when no data directory can be derived.
String containerPathFor(String appId, {Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final home = env['HOME'];
  if (Platform.isMacOS) {
    if (home == null || home.isEmpty) {
      throw const KeystoreUnreachable(
          'HOME is not set; cannot derive the application data directory');
    }
    return '$home/Library/Application Support/$appId/$containerFileName';
  }
  if (Platform.isLinux) {
    final xdg = env['XDG_DATA_HOME'];
    if (xdg != null && xdg.startsWith('/')) {
      return '$xdg/$appId/$containerFileName';
    }
    if (home == null || home.isEmpty) {
      throw const KeystoreUnreachable(
          'neither XDG_DATA_HOME nor HOME is set; cannot derive the '
          'application data directory');
    }
    return '$home/.local/share/$appId/$containerFileName';
  }
  throw KeystoreUnreachable(
      'no secret storage scheme for ${Platform.operatingSystem}');
}

/// Derives the Android app data directory from
/// `System.getProperty("java.io.tmpdir")` — which the framework sets to the
/// app's **cache** dir (`<dataDir>/cache`) — giving `<dataDir>` without
/// needing an `android.content.Context` (no hidden APIs; `files` and `cache`
/// are sibling children of `dataDir` per the stable `ApplicationInfo` layout).
///
/// Pure and strict: anything other than an absolute path ending in `/cache`
/// throws [KeystoreUnreachable] rather than guessing at a location that will
/// hold key material.
String androidDataDirFromTmpdir(String tmpdir) {
  // Tolerate a single trailing slash; reject anything else surprising.
  final normalized = tmpdir.endsWith('/') && tmpdir.length > 1
      ? tmpdir.substring(0, tmpdir.length - 1)
      : tmpdir;
  final dataDir = normalized.startsWith('/') && normalized.endsWith('/cache')
      ? normalized.substring(0, normalized.length - '/cache'.length)
      : '';
  if (dataDir.isEmpty) {
    throw const KeystoreUnreachable(
        'unexpected java.io.tmpdir layout on Android; cannot derive the '
        'app data directory');
  }
  return dataDir;
}

/// The Android no-backup directory derived from the framework cache path.
///
/// Android exposes this directory as `Context.noBackupFilesDir`, but a pure
/// Dart package has no supported API for obtaining the process `Context`.
/// `java.io.tmpdir` is the app cache directory, whose stable sibling is the
/// no-backup directory. The Android integration harness independently compares
/// this result with the public `Context.getNoBackupFilesDir()` API on every
/// supported emulator tier.
String androidNoBackupDirFromTmpdir(String tmpdir) =>
    '${androidDataDirFromTmpdir(tmpdir)}/no_backup';

/// The Android container path:
/// `<dataDir>/no_backup/<appId>/secrets.enc`.
/// [appId] must already have passed `validateAppId`; [tmpdir] is the value of
/// `System.getProperty("java.io.tmpdir")` (see [androidDataDirFromTmpdir]).
String androidContainerPathFor(String appId, {required String tmpdir}) =>
    '${androidNoBackupDirFromTmpdir(tmpdir)}/$appId/$containerFileName';

/// The Android 0.1.0 container path. Used only to migrate an existing
/// installation into [androidContainerPathFor].
String androidLegacyContainerPathFor(String appId, {required String tmpdir}) =>
    '${androidDataDirFromTmpdir(tmpdir)}/files/$appId/$containerFileName';

/// Atomically moves an Android 0.1.0 store directory into the no-backup
/// namespace. The container and every sidecar move together, so the Android
/// Keystore alias and wrapped store key remain unchanged.
///
/// A same-filesystem directory rename is the migration transaction: after a
/// crash the complete directory is visible at either the legacy or current
/// location, never partially copied. If both locations contain state, neither
/// is modified and [StoreMigrationConflict] is thrown. A restored legacy store
/// still migrates as opaque ciphertext; its first operation then surfaces the
/// existing [KeyInvalidated] result if the device-bound Keystore key is absent.
void migrateLegacyAndroidStore(
  String appId, {
  required String tmpdir,
  SecureFileSystem fs = const SecureFileSystem(),
}) {
  String parentOf(String path) => path.substring(0, path.lastIndexOf('/'));

  final currentDir = parentOf(androidContainerPathFor(appId, tmpdir: tmpdir));
  final legacyDir =
      parentOf(androidLegacyContainerPathFor(appId, tmpdir: tmpdir));
  final currentType = FileSystemEntity.typeSync(currentDir, followLinks: false);
  final legacyType = FileSystemEntity.typeSync(legacyDir, followLinks: false);

  if (currentType != FileSystemEntityType.notFound) {
    if (currentType != FileSystemEntityType.directory) {
      throw SecureFileError('android-current-not-directory', currentDir, 0);
    }
    if (legacyType != FileSystemEntityType.notFound) {
      throw StoreMigrationConflict(
        appId: appId,
        legacyPath: legacyDir,
        currentPath: currentDir,
      );
    }
    return;
  }
  if (legacyType == FileSystemEntityType.notFound) return;
  if (legacyType != FileSystemEntityType.directory) {
    throw SecureFileError('android-legacy-not-directory', legacyDir, 0);
  }
  if (!fs.verifyPrivateDirSync(legacyDir)) {
    throw SecureFileError('android-legacy-vanished', legacyDir, 0);
  }

  final noBackupRoot = parentOf(currentDir);
  // ContextImpl creates this framework-owned root with 0771 on current
  // Android releases, just like filesDir. Keybay's appId child remains 0700
  // and holds every store artifact; do not apply the encrypted-store leaf's
  // stricter mode policy to its Android-managed parent.
  var rootType = FileSystemEntity.typeSync(noBackupRoot, followLinks: false);
  if (rootType == FileSystemEntityType.notFound) {
    try {
      Directory(noBackupRoot).createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw SecureFileError(
        'create-android-no-backup-root',
        noBackupRoot,
        error.osError?.errorCode ?? 0,
      );
    }
    rootType = FileSystemEntity.typeSync(noBackupRoot, followLinks: false);
  }
  if (rootType != FileSystemEntityType.directory) {
    throw SecureFileError(
        'android-no-backup-root-not-directory', noBackupRoot, 0);
  }
  try {
    Directory(legacyDir).renameSync(currentDir);
  } on FileSystemException catch (error) {
    // A concurrent resolver may have completed the same atomic migration
    // after our initial observations. Treat exactly that final state as
    // success; every other failure stays typed and loud.
    final sourceNow = FileSystemEntity.typeSync(legacyDir, followLinks: false);
    final targetNow = FileSystemEntity.typeSync(currentDir, followLinks: false);
    if (sourceNow == FileSystemEntityType.notFound &&
        targetNow == FileSystemEntityType.directory) {
      return;
    }
    throw SecureFileError(
      'migrate-legacy-android-store',
      legacyDir,
      error.osError?.errorCode ?? 0,
    );
  }
}

/// Beside the possible macOS encrypted container so the signing configuration
/// sees one stable trace across file/native scheme transitions.
String macosSchemeMarkerPathFor(String appId,
    {Map<String, String>? environment}) {
  final container = containerPathFor(appId, environment: environment);
  final i = container.lastIndexOf('/');
  return '${container.substring(0, i)}/$macosSchemeMarkerFileName';
}

/// A Linux session-private lock path shared by every container root for one
/// Secret Service identity. It intentionally does not depend on
/// HOME/XDG_DATA_HOME: two processes that point their containers at different
/// data roots must still coordinate creation of the one shared Secret Service
/// key. `XDG_RUNTIME_DIR` is the desktop session's private, user-owned runtime
/// namespace; unlike a predictable directory under `/tmp`, another OS user
/// cannot pre-create this path and deny all Keybay writes.
///
/// The runtime directory must already exist. The caller verifies that boundary
/// before allowing [SystemKeySource] to create the `keybay` child directory.
/// Apple uses the Keychain's atomic add-if-absent primitive instead: no runtime
/// lock is needed there.
String coordinationLockPathFor(
  String appId, {
  Map<String, String>? environment,
}) {
  final runtimeDir = (environment ?? Platform.environment)['XDG_RUNTIME_DIR'];
  if (runtimeDir == null || runtimeDir.isEmpty || !runtimeDir.startsWith('/')) {
    throw const KeystoreUnreachable(
      'XDG_RUNTIME_DIR is not an absolute path; a private desktop runtime '
      'directory is required for Linux store coordination',
    );
  }
  final normalized = runtimeDir.length > 1 && runtimeDir.endsWith('/')
      ? runtimeDir.substring(0, runtimeDir.length - 1)
      : runtimeDir;
  return '$normalized/keybay/$appId.store-key.lock';
}
