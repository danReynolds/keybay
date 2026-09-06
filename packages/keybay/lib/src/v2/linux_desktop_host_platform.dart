/// Candidate host binding for the ordinary Linux Secret Service profile.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';

import '../errors.dart';
import 'application_identity.dart';
import 'flatpak_host_platform.dart' show currentProcessHasFlatpakMarker;
import 'host_platform.dart';
import 'linux_secret_service_protector.dart';
import 'linux_secret_service_root_store.dart';
import 'platform_protector.dart';
import 'posix_store_files.dart';
import 'store_files.dart';

/// Frozen qualification label for this exact identity/files/provider tuple.
const String linuxDesktopProfileCode = 'linux.desktop.secret-service-file.v1';

final HostProfile _linuxDesktopProfile = HostProfile(linuxDesktopProfileCode);

/// Resolves an ordinary, unsandboxed Linux process to XDG files and one
/// Secret Service root over a non-interactive, bytes-only D-Bus adapter.
///
/// This profile is namespace-only. It deliberately refuses an observed
/// Flatpak sandbox or Snap security label: confined processes belong to
/// different complete profiles and are never downgraded to raw Secret Service.
final class LinuxDesktopHostPlatform implements HostPlatform {
  LinuxDesktopHostPlatform()
    : _isLinux = Platform.isLinux,
      _isFlatpak = currentProcessHasFlatpakMarker,
      _isSnap =
          _environmentHasSnapHint(Platform.environment) ||
          _currentProcessHasSnapAppArmorLabel(),
      _resolveIdentity = DartApplicationIdentityResolver.resolveCurrentProcess,
      _environment = Platform.environment,
      _canonicalFileRoot = null,
      _rootStore = null;

  /// Deterministic constructor for this profile's integration tests.
  LinuxDesktopHostPlatform.test({
    ApplicationIdentity? identity,
    Future<ApplicationIdentity> Function()? identityResolver,
    required LinuxSecretServiceRootStore rootStore,
    Uri? canonicalFileRoot,
    Map<String, String> environment = const <String, String>{},
    bool isLinux = true,
    bool isFlatpak = false,
    bool? isSnap,
  }) : assert(identity != null || identityResolver != null),
       _isLinux = isLinux,
       _isFlatpak = (() => isFlatpak),
       _isSnap = isSnap ?? _environmentHasSnapHint(environment),
       _resolveIdentity = identityResolver ?? (() async => identity!),
       _environment = Map<String, String>.unmodifiable(environment),
       _canonicalFileRoot = canonicalFileRoot,
       _rootStore = rootStore;

  final bool _isLinux;
  final bool Function() _isFlatpak;
  final bool _isSnap;
  final Future<ApplicationIdentity> Function() _resolveIdentity;
  final Map<String, String> _environment;
  final Uri? _canonicalFileRoot;
  final LinuxSecretServiceRootStore? _rootStore;

  @override
  Future<ResolvedHost> resolve() async {
    if (!_isLinux || _isFlatpak() || _isSnap) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }

    final identity = await _resolveIdentity();
    if (identity.assurance != ApplicationIdentityAssurance.namespaceOnly) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }

    try {
      final root =
          _canonicalFileRoot ??
          _productionFileRoot(identity, environment: _environment);
      final binding = ResolvedApplicationBinding.derive(
        identity: identity,
        profile: _linuxDesktopProfile,
        canonicalFileRoot: root,
      );
      final files = PosixStoreFiles(binding: binding, canonicalFileRoot: root);
      final roots =
          _rootStore ??
          DbusLinuxSecretServiceRootStore(
            runtimeDirectory: _runtimeDirectory(_environment),
          );
      final protector = LinuxSecretServiceProtector(
        binding: binding,
        roots: roots,
      );
      return ResolvedHost(binding: binding, files: files, protector: protector);
    } on PlatformProtectorFailure {
      rethrow;
    } on StoreFilesFailure {
      rethrow;
    } on KeystoreLocked {
      throw const PlatformProtectorFailure(PlatformProtectorFailureCode.locked);
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

bool _environmentHasSnapHint(Map<String, String> environment) =>
    (environment['SNAP']?.isNotEmpty ?? false) ||
    (environment['SNAP_NAME']?.isNotEmpty ?? false);

bool _currentProcessHasSnapAppArmorLabel() {
  RandomAccessFile? current;
  try {
    current = File('/proc/self/attr/current').openSync();
    return linuxAppArmorLabelIdentifiesSnap(current.readSync(5));
  } on FileSystemException {
    // An unavailable label cannot prove confinement. The ordinary profile
    // remains namespace-only, while the normal Snap environment is retained as
    // an additional fail-closed hint.
    return false;
  } finally {
    try {
      current?.closeSync();
    } on FileSystemException {
      // Reading the immutable process label already established the result.
    }
  }
}

/// Recognizes snapd's kernel-assigned `snap.` AppArmor security-tag prefix.
///
/// Exposed only from internal package source for hermetic boundary tests. It
/// derives no identity and grants no assurance; a positive result only refuses
/// the ordinary Linux profile.
bool linuxAppArmorLabelIdentifiesSnap(List<int> prefix) =>
    prefix.length >= 5 &&
    prefix[0] == 0x73 &&
    prefix[1] == 0x6e &&
    prefix[2] == 0x61 &&
    prefix[3] == 0x70 &&
    prefix[4] == 0x2e;

Uri _productionFileRoot(
  ApplicationIdentity identity, {
  required Map<String, String> environment,
}) {
  final base = _dataHome(environment);
  final canonicalBase = _prepareDataHome(base);
  final digest = const DartSha256()
      .hashSync(
        utf8.encode(
          'keybay:v2:linux-desktop:file-root\u0000'
          '${identity.assurance.wireCode}\u0000'
          '$linuxDesktopProfileCode\u0000'
          '${identity.stableValue}',
        ),
      )
      .bytes;
  final suffix = digest
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return Uri.directory(
    '$canonicalBase/${identity.stableValue}-$suffix.keybay-v2',
  );
}

String _prepareDataHome(String requestedPath) {
  try {
    return _prepareDataHomeChecked(requestedPath);
  } on StoreFilesFailure {
    rethrow;
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

String _prepareDataHomeChecked(String requestedPath) {
  var candidate = requestedPath;
  while (candidate.length > 1 && candidate.endsWith('/')) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  if (!candidate.startsWith('/') ||
      candidate.contains('\u0000') ||
      (candidate != '/' &&
          candidate
              .substring(1)
              .split('/')
              .any(
                (component) =>
                    component.isEmpty || component == '.' || component == '..',
              ))) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }

  final missing = <String>[];
  while (true) {
    final type = FileSystemEntity.typeSync(candidate, followLinks: false);
    if (type == FileSystemEntityType.directory ||
        (type == FileSystemEntityType.link &&
            Directory(candidate).existsSync())) {
      final canonicalParent = Directory(candidate).resolveSymbolicLinksSync();
      if (missing.isNotEmpty) {
        PosixStoreFiles.durablyCreatePrivateDirectories(
          canonicalExistingParent: Uri.directory(canonicalParent),
          childComponents: missing,
        );
      }
      final prepared = missing.isEmpty
          ? canonicalParent
          : '$canonicalParent/${missing.join('/')}';
      return Directory(prepared).resolveSymbolicLinksSync();
    }
    if (type != FileSystemEntityType.notFound) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }

    final separator = candidate.lastIndexOf('/');
    if (separator < 0 || separator == candidate.length - 1) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    missing.insert(0, candidate.substring(separator + 1));
    candidate = separator == 0 ? '/' : candidate.substring(0, separator);
  }
}

String _dataHome(Map<String, String> environment) {
  final declared = environment['XDG_DATA_HOME'];
  if (declared != null && declared.startsWith('/')) {
    return declared;
  }
  final home = environment['HOME'];
  if (home == null || !home.startsWith('/')) {
    throw const KeystoreUnreachable('No absolute XDG data home is available');
  }
  return '$home/.local/share';
}

String _runtimeDirectory(Map<String, String> environment) {
  final runtime = environment['XDG_RUNTIME_DIR'];
  if (runtime == null || !runtime.startsWith('/')) {
    throw const KeystoreUnreachable(
      'No absolute XDG runtime directory is available',
    );
  }
  return runtime;
}
