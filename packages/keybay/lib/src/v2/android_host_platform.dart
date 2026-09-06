/// Complete host binding for the Android 12+ application profile.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../errors.dart';
import '../ffi/jni.dart';
import 'android_keystore_protector.dart';
import 'application_identity.dart';
import 'host_platform.dart';
import 'platform_protector.dart';
import 'posix_store_files.dart';
import 'store_files.dart';

/// Frozen qualification label for Android's sandbox/files/Keystore tuple.
const String androidHostProfileCode = 'android.api31.keystore-file.v1';

final HostProfile _androidProfile = HostProfile(androidHostProfileCode);

/// OS-derived Android application facts resolved before persisted bytes.
final class AndroidHostFacts {
  const AndroidHostFacts({
    required this.packageName,
    required this.uid,
    required this.noBackupRoot,
  });

  final String packageName;
  final int uid;
  final Uri noBackupRoot;
}

/// Resolves one Android application sandbox to its no-backup directory and
/// one non-exportable Android Keystore root.
final class AndroidHostPlatform implements HostPlatform {
  AndroidHostPlatform()
    : _isAndroid = Platform.isAndroid,
      _resolveFacts = _resolveCurrentAndroidHostFacts,
      _keystore = null;

  /// Deterministic constructor for profile integration tests.
  AndroidHostPlatform.test({
    required AndroidHostFacts facts,
    required AndroidKeystoreAead keystore,
    bool isAndroid = true,
  }) : _isAndroid = isAndroid,
       _resolveFacts = (() async => facts),
       _keystore = keystore;

  final bool _isAndroid;
  final Future<AndroidHostFacts> Function() _resolveFacts;
  final AndroidKeystoreAead? _keystore;

  @override
  Future<ResolvedHost> resolve() async {
    if (!_isAndroid) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }

    try {
      final facts = await _resolveFacts();
      final identity = ApplicationIdentity(
        stableValue: facts.packageName,
        source: ApplicationIdentitySource.operatingSystem,
        assurance: ApplicationIdentityAssurance.osEnforced,
      );
      final binding = ResolvedApplicationBinding.derive(
        identity: identity,
        profile: _androidProfile,
        canonicalFileRoot: facts.noBackupRoot,
      );
      final files = PosixStoreFiles.fromExistingPrivateRoot(
        binding: binding,
        canonicalFileRoot: facts.noBackupRoot,
      );
      final protector = AndroidKeystoreProtector(
        binding: binding,
        keystore: _keystore,
      );
      return ResolvedHost(binding: binding, files: files, protector: protector);
    } on ApplicationIdentityFailure {
      rethrow;
    } on PlatformProtectorFailure {
      rethrow;
    } on StoreFilesFailure {
      rethrow;
    } on KeystoreUnreachable {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    } on SecretStoreException {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    } on FileSystemException {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
  }
}

Future<AndroidHostFacts> _resolveCurrentAndroidHostFacts() async {
  final jni = Jni.instance();
  final uid = _getUid();
  final processName = jni.androidProcessName();
  final declaredTemp = jni.systemProperty('java.io.tmpdir');
  // `/data/user/<n>` is an Android-owned compatibility path that currently
  // resolves through `/data/data` for user 0. Preserve the framework spelling
  // instead of using realpath: it is the stable public Context path and the
  // identity grammar below verifies its complete shape.
  final canonicalCache = _existingAndroidDirectoryPath(declaredTemp);
  final facts = resolveAndroidHostFactsFromCanonicalCache(
    canonicalCache: canonicalCache,
    processName: processName,
    uid: uid,
  );
  final packageRoot = File(canonicalCache).parent.path;
  final noBackupPath = '$packageRoot/no_backup';
  _requireAndroidOwnedDirectory(jni, packageRoot, uid: uid);
  _requireAndroidOwnedDirectory(jni, canonicalCache, uid: uid);

  final createdNoBackup = _ensureDirectory(noBackupPath);
  _requireAndroidOwnedDirectory(jni, noBackupPath, uid: uid);
  if (createdNoBackup) {
    PosixStoreFiles.durablyAnchorPrivateRoot(
      canonicalFileRoot: Uri.directory(noBackupPath),
    );
  }

  final storeRoot = '$noBackupPath/$_keybayDirectoryName';
  _ensureDirectory(storeRoot);
  _requirePrivateAndroidDirectory(jni, storeRoot, uid: uid);
  // Anchor this fixed private child on every resolution. This also closes the
  // concurrent-creator window where this process observed EEXIST before the
  // creator had synced the new parent entry.
  PosixStoreFiles.durablyAnchorPrivateRoot(
    canonicalFileRoot: Uri.directory(storeRoot),
  );

  return AndroidHostFacts(
    packageName: facts.packageName,
    uid: facts.uid,
    noBackupRoot: Uri.directory(storeRoot),
  );
}

/// Applies the fixed Android package/process/path relationship to canonical
/// host facts. Exposed only from internal package source for hermetic tests.
AndroidHostFacts resolveAndroidHostFactsFromCanonicalCache({
  required String canonicalCache,
  required String processName,
  required int uid,
}) {
  final match = _androidCachePath.firstMatch(canonicalCache);
  if (match == null) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }

  final user = int.parse(match.group(1)!);
  final packageName = match.group(2)!;
  final processSuffix = processName.startsWith('$packageName:')
      ? processName.substring(packageName.length + 1)
      : null;
  if (uid < 0 ||
      uid ~/ 100000 != user ||
      !_androidPackageName.hasMatch(packageName) ||
      (processName != packageName &&
          (processSuffix == null ||
              !_androidProcessSuffix.hasMatch(processSuffix)))) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }

  final packageRoot = File(canonicalCache).parent.path;
  final noBackupPath = '$packageRoot/no_backup/$_keybayDirectoryName';
  return AndroidHostFacts(
    packageName: packageName,
    uid: uid,
    noBackupRoot: Uri.directory(noBackupPath),
  );
}

String _existingAndroidDirectoryPath(String path) {
  final normalized = _withoutTrailingSlash(path);
  if (!normalized.startsWith('/') || normalized.contains('\u0000')) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }
  if (FileSystemEntity.typeSync(normalized, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  return normalized;
}

String _withoutTrailingSlash(String path) {
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2f) {
    end -= 1;
  }
  return end == path.length ? path : path.substring(0, end);
}

void _requirePrivateAndroidDirectory(Jni jni, String path, {required int uid}) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  final stat = jni.androidStat(path);
  if (stat.uid != uid ||
      stat.mode & _fileTypeMask != _directoryType ||
      stat.mode & _groupOtherPermissionMask != 0) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

void _requireAndroidOwnedDirectory(Jni jni, String path, {required int uid}) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  final stat = jni.androidStat(path);
  if (stat.uid != uid || stat.mode & _fileTypeMask != _directoryType) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

bool _ensureDirectory(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.directory) return false;
  if (type != FileSystemEntityType.notFound) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }

  var created = false;
  final pointer = path.toNativeUtf8();
  try {
    if (_mkdir(pointer, _ownerOnlyDirectoryMode) == 0) {
      created = true;
    } else {
      final error = _errno;
      if (error != _alreadyExists) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
    }
  } finally {
    malloc.free(pointer);
  }

  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  return created;
}

final RegExp _androidCachePath = RegExp(
  r'^/data/user/([0-9]+)/([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)/cache$',
);
final RegExp _androidPackageName = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
);
final RegExp _androidProcessSuffix = RegExp(r'^[A-Za-z0-9._-]{1,120}$');

const int _ownerOnlyDirectoryMode = 0x1c0;
const int _groupOtherPermissionMask = 0x3f;
const int _fileTypeMask = 0xf000;
const int _directoryType = 0x4000;
const int _alreadyExists = 17;
const String _keybayDirectoryName = 'keybay-v2';

final DynamicLibrary _libc = DynamicLibrary.process();

final int Function() _getUid = _libc
    .lookupFunction<Uint32 Function(), int Function()>('getuid');

final int Function(Pointer<Utf8>, int) _mkdir = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('mkdir');

final Pointer<Int32> Function() _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      '__errno',
    );

int get _errno => _errnoLocation().value;
