/// Complete V2 host profiles for iOS and entitled macOS applications.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:ffi/ffi.dart';

import '../errors.dart';
import '../ffi/apple_host.dart';
import 'apple_data_protection_keychain_protector.dart';
import 'apple_data_protection_keychain_root_store.dart';
import 'application_identity.dart';
import 'host_platform.dart';
import 'platform_protector.dart';
import 'posix_store_files.dart';
import 'store_files.dart';

/// Signed Info.plist key expanded at build time on iOS.
///
/// Its value is `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`. The
/// signed bundle supplies it; application code and persisted store metadata do
/// not select an identity or Keychain group at runtime.
const String iosApplicationIdentifierInfoKey = 'KeybayApplicationIdentifier';

const String iosDataProtectionProfileCode =
    'ios.signed.data-protection-file.v1';
const String macOSEntitledDataProtectionProfileCode =
    'macos.entitled.data-protection-file.v1';

final HostProfile _iosProfile = HostProfile(iosDataProtectionProfileCode);
final HostProfile _macOSEntitledProfile = HostProfile(
  macOSEntitledDataProtectionProfileCode,
);

/// Resolved iOS facts. Production constructs this only after the private file
/// root has been durably created and its backup exclusion verified.
final class IOSHostFacts {
  const IOSHostFacts._({
    required this.bundleIdentifier,
    required this.applicationIdentifier,
    required this.canonicalFileRoot,
  });

  final String bundleIdentifier;
  final String applicationIdentifier;
  final Uri canonicalFileRoot;
}

/// Resolved entitled-macOS facts.
final class MacOSEntitledHostFacts {
  const MacOSEntitledHostFacts._({
    required this.bundleIdentifier,
    required this.applicationIdentifier,
    required this.canonicalFileRoot,
  });

  final String bundleIdentifier;
  final String applicationIdentifier;
  final Uri canonicalFileRoot;
}

/// Resolves and assembles the one signed iOS application store.
final class IOSHostPlatform implements HostPlatform {
  IOSHostPlatform()
    : _isIOS = Platform.isIOS,
      _resolveFacts = _resolveCurrentIOSHostFacts,
      _rootStore = null;

  /// Deterministic assembly constructor. [facts] must name an already-existing
  /// private root, mirroring the production resolver's completed result.
  IOSHostPlatform.test({
    required IOSHostFacts facts,
    required DataProtectionKeychainRootStore rootStore,
    bool isIOS = true,
  }) : _isIOS = isIOS,
       _resolveFacts = (() async => facts),
       _rootStore = rootStore;

  final bool _isIOS;
  final Future<IOSHostFacts> Function() _resolveFacts;
  final DataProtectionKeychainRootStore? _rootStore;

  @override
  Future<ResolvedHost> resolve() => _atAppleHostBoundary(() async {
    if (!_isIOS) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }
    final facts = await _resolveFacts();
    _validateSignedIdentifier(
      bundleIdentifier: facts.bundleIdentifier,
      applicationIdentifier: facts.applicationIdentifier,
    );
    return _assembleDataProtectionHost(
      binding: ResolvedApplicationBinding.forApplicationContainer(
        identity: _signedIdentity(facts.applicationIdentifier),
        profile: _iosProfile,
        canonicalFileRoot: facts.canonicalFileRoot,
        containerRelativeRoot: Uri.parse(
          'Library/Application%20Support/keybay-v2/',
        ),
      ),
      rootStore: _rootStore,
    );
  });
}

/// Resolves the signed macOS application-identifier and its Application Support
/// root. App Sandbox status affects only how that root is obtained; it does not
/// create a second provider profile. The host never downgrades to the
/// login-Keychain profile when entitlement or Data Protection access fails.
final class MacOSEntitledHostPlatform implements HostPlatform {
  MacOSEntitledHostPlatform()
    : _isMacOS = Platform.isMacOS,
      _resolveFacts = _resolveCurrentMacOSEntitledHostFacts,
      _rootStore = null;

  /// Deterministic assembly constructor for an already-prepared file root.
  MacOSEntitledHostPlatform.test({
    required MacOSEntitledHostFacts facts,
    required DataProtectionKeychainRootStore rootStore,
    bool isMacOS = true,
  }) : _isMacOS = isMacOS,
       _resolveFacts = (() async => facts),
       _rootStore = rootStore;

  final bool _isMacOS;
  final Future<MacOSEntitledHostFacts> Function() _resolveFacts;
  final DataProtectionKeychainRootStore? _rootStore;

  @override
  Future<ResolvedHost> resolve() => _atAppleHostBoundary(() async {
    if (!_isMacOS) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }
    final facts = await _resolveFacts();
    _validateSignedIdentifier(
      bundleIdentifier: facts.bundleIdentifier,
      applicationIdentifier: facts.applicationIdentifier,
    );
    return _assembleDataProtectionHost(
      binding: ResolvedApplicationBinding.derive(
        identity: _signedIdentity(facts.applicationIdentifier),
        profile: _macOSEntitledProfile,
        canonicalFileRoot: facts.canonicalFileRoot,
      ),
      rootStore: _rootStore,
    );
  });
}

ApplicationIdentity _signedIdentity(String applicationIdentifier) =>
    ApplicationIdentity(
      stableValue: applicationIdentifier,
      source: ApplicationIdentitySource.operatingSystem,
      assurance: ApplicationIdentityAssurance.osEnforced,
    );

ResolvedHost _assembleDataProtectionHost({
  required ResolvedApplicationBinding binding,
  required DataProtectionKeychainRootStore? rootStore,
}) {
  final files = PosixStoreFiles.fromExistingPrivateRoot(
    binding: binding,
    canonicalFileRoot: binding.canonicalFileRoot,
  );
  final roots =
      rootStore ??
      AppleDataProtectionKeychainRootStore(
        exactApplicationIdentifierAccessGroup: binding.identity.stableValue,
      );
  return ResolvedHost(
    binding: binding,
    files: files,
    protector: AppleDataProtectionKeychainProtector(
      binding: binding,
      roots: roots,
    ),
  );
}

Future<T> _atAppleHostBoundary<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on ApplicationIdentityFailure {
    rethrow;
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

/// Pure iOS binding resolution used by production and hermetic tests.
IOSHostFacts resolveIOSHostFacts({
  required String bundleIdentifier,
  required String applicationIdentifier,
  required Uri applicationSupportRoot,
}) {
  _validateSignedIdentifier(
    bundleIdentifier: bundleIdentifier,
    applicationIdentifier: applicationIdentifier,
  );
  _validateCanonicalDirectoryUri(applicationSupportRoot);
  return IOSHostFacts._(
    bundleIdentifier: bundleIdentifier,
    applicationIdentifier: applicationIdentifier,
    canonicalFileRoot: Uri.directory(
      '${_directoryPath(applicationSupportRoot)}/keybay-v2',
    ),
  );
}

/// Pure macOS binding resolution used by production and hermetic tests.
MacOSEntitledHostFacts resolveMacOSEntitledHostFacts({
  required String bundleIdentifier,
  required String applicationIdentifier,
  required Uri applicationSupportRoot,
}) {
  _validateSignedIdentifier(
    bundleIdentifier: bundleIdentifier,
    applicationIdentifier: applicationIdentifier,
  );
  _validateCanonicalDirectoryUri(applicationSupportRoot);
  final digest = const DartSha256()
      .hashSync(
        utf8.encode(
          'keybay:v2:macos-entitled:file-root\u0000'
          '$macOSEntitledDataProtectionProfileCode\u0000'
          '$applicationIdentifier',
        ),
      )
      .bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return MacOSEntitledHostFacts._(
    bundleIdentifier: bundleIdentifier,
    applicationIdentifier: applicationIdentifier,
    canonicalFileRoot: Uri.directory(
      '${_directoryPath(applicationSupportRoot)}/keybay-v2-$digest',
    ),
  );
}

/// Creates and durably anchors one fixed private Apple application-store root.
/// Existing non-directories, symlinks, and non-0700 directories fail closed.
void prepareApplePrivateStoreRoot(Uri canonicalFileRoot) {
  _validateCanonicalDirectoryUri(canonicalFileRoot, requireExisting: false);
  final path = _directoryPath(canonicalFileRoot);
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    final nativePath = path.toNativeUtf8();
    try {
      if (_mkdir(nativePath, _ownerOnlyDirectoryMode) != 0 &&
          _errno != _alreadyExists) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
    } finally {
      malloc.free(nativePath);
    }
  } else if (type != FileSystemEntityType.directory) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  PosixStoreFiles.durablyAnchorPrivateRoot(
    canonicalFileRoot: canonicalFileRoot,
  );
}

Future<IOSHostFacts> _resolveCurrentIOSHostFacts() async {
  final api = AppleHostApi.ios();
  final bundleIdentifier = _readIdentity(api.bundleIdentifier);
  final applicationIdentifier = _readIdentity(
    () => api.infoString(iosApplicationIdentifierInfoKey),
  );
  final support = _resolveApplicationSupport(api, createIfMissing: true);
  final facts = resolveIOSHostFacts(
    bundleIdentifier: bundleIdentifier,
    applicationIdentifier: applicationIdentifier,
    applicationSupportRoot: support,
  );
  prepareApplePrivateStoreRoot(facts.canonicalFileRoot);
  try {
    api.setAndVerifyBackupExcluded(facts.canonicalFileRoot);
    PosixStoreFiles.durablyAnchorPrivateRoot(
      canonicalFileRoot: facts.canonicalFileRoot,
    );
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  return facts;
}

Future<MacOSEntitledHostFacts> _resolveCurrentMacOSEntitledHostFacts() async {
  final api = AppleHostApi.macOS();
  final bundleIdentifier = _readIdentity(api.bundleIdentifier);
  final applicationIdentifier = _readIdentity(
    api.macOSSignedApplicationIdentifier,
  );
  final sandboxed = _readIdentity(api.macOSAppSandboxEnabled);
  final support = _resolveApplicationSupport(api, createIfMissing: sandboxed);
  final facts = resolveMacOSEntitledHostFacts(
    bundleIdentifier: bundleIdentifier,
    applicationIdentifier: applicationIdentifier,
    applicationSupportRoot: support,
  );
  prepareApplePrivateStoreRoot(facts.canonicalFileRoot);
  return facts;
}

T _readIdentity<T>(T Function() operation) {
  try {
    return operation();
  } on ApplicationIdentityFailure {
    rethrow;
  } on Object {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }
}

Uri _resolveApplicationSupport(
  AppleHostApi api, {
  required bool createIfMissing,
}) {
  try {
    final declared = api.applicationSupportDirectory();
    if (!declared.startsWith('/') || declared.contains('\u0000')) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    final declaredType = FileSystemEntity.typeSync(
      declared,
      followLinks: false,
    );
    if (declaredType == FileSystemEntityType.notFound && createIfMissing) {
      final parent = File(declared).parent.path;
      if (FileSystemEntity.typeSync(parent, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      }
      final nativePath = declared.toNativeUtf8();
      var created = false;
      try {
        if (_mkdir(nativePath, _ownerOnlyDirectoryMode) == 0) {
          created = true;
        } else if (_errno != _alreadyExists) {
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }
      } finally {
        malloc.free(nativePath);
      }
      if (created) {
        PosixStoreFiles.durablyAnchorPrivateRoot(
          canonicalFileRoot: Uri.directory(declared),
        );
      }
    }
    final directory = Directory(declared);
    if (FileSystemEntity.typeSync(declared, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
    }
    return Uri.directory(directory.resolveSymbolicLinksSync());
  } on StoreFilesFailure {
    rethrow;
  } on Object {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

void _validateSignedIdentifier({
  required String bundleIdentifier,
  required String applicationIdentifier,
}) {
  if (!_bundleIdentifierGrammar.hasMatch(bundleIdentifier) ||
      applicationIdentifier.length > 120 ||
      !_applicationIdentifierGrammar.hasMatch(applicationIdentifier) ||
      !applicationIdentifier.endsWith('.$bundleIdentifier')) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.invalidDeclaration,
    );
  }
  final prefixLength =
      applicationIdentifier.length - bundleIdentifier.length - 1;
  if (prefixLength < 1 ||
      !_appIdentifierPrefixGrammar.hasMatch(
        applicationIdentifier.substring(0, prefixLength),
      )) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.invalidDeclaration,
    );
  }
}

void _validateCanonicalDirectoryUri(Uri root, {bool requireExisting = true}) {
  if (root.scheme != 'file' ||
      !root.isAbsolute ||
      root.hasQuery ||
      root.hasFragment ||
      !root.path.endsWith('/') ||
      root.normalizePath() != root ||
      root.toString().length > 4096) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
  if (requireExisting &&
      FileSystemEntity.typeSync(_directoryPath(root), followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
  }
}

String _directoryPath(Uri directory) {
  final path = directory.toFilePath();
  var end = path.length;
  while (end > 1 && path.codeUnitAt(end - 1) == 0x2f) {
    end -= 1;
  }
  return end == path.length ? path : path.substring(0, end);
}

final RegExp _bundleIdentifierGrammar = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+$',
);
final RegExp _applicationIdentifierGrammar = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9.-]{2,119}$',
);
final RegExp _appIdentifierPrefixGrammar = RegExp(r'^[A-Za-z0-9]{1,64}$');

const int _ownerOnlyDirectoryMode = 0x1c0;
const int _alreadyExists = 17;

final DynamicLibrary _libc = DynamicLibrary.process();
final int Function(Pointer<Utf8>, int) _mkdir = _libc
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('mkdir');
final Pointer<Int32> Function() _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      '__error',
    );
int get _errno => _errnoLocation().value;
