/// Complete host binding for the macOS unentitled application/CLI profile.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';

import '../errors.dart';
import '../ffi/apple_host.dart';
import 'application_identity.dart';
import 'host_platform.dart';
import 'macos_account_home.dart';
import 'macos_login_keychain_protector.dart';
import 'macos_login_keychain_root_store.dart';
import 'platform_protector.dart';
import 'posix_store_files.dart';
import 'store_files.dart';

/// Frozen qualification label for this exact identity/files/provider tuple.
const String macOSUnentitledProfileCode =
    'macos.unentitled.login-file-keychain.v1';

final HostProfile _macOSUnentitledProfile = HostProfile(
  macOSUnentitledProfileCode,
);

/// Resolves one namespace-only macOS application to private files and the
/// effective account's explicit login Keychain.
///
/// A process with a Data Protection Keychain access group is deliberately
/// rejected. It belongs to the entitled host profile and is never downgraded
/// to this one.
final class MacOSUnentitledHostPlatform implements HostPlatform {
  MacOSUnentitledHostPlatform()
    : _isMacOS = Platform.isMacOS,
      _resolveIdentity = DartApplicationIdentityResolver.resolveCurrentProcess,
      _hasSignedApplicationIdentifier =
          _currentProcessHasSignedApplicationIdentifier,
      _canonicalFileRoot = null,
      _rootStore = null;

  /// Deterministic constructor for this profile's integration tests.
  ///
  /// This remains internal package source and cannot select a production
  /// identity, path, profile, or provider through the public Keybay API.
  MacOSUnentitledHostPlatform.test({
    required ApplicationIdentity identity,
    required Uri canonicalFileRoot,
    required MacOSLoginKeychainRootStore rootStore,
    bool isMacOS = true,
    bool hasSignedApplicationIdentifier = false,
  }) : _isMacOS = isMacOS,
       _resolveIdentity = (() async => identity),
       _hasSignedApplicationIdentifier = (() => hasSignedApplicationIdentifier),
       _canonicalFileRoot = canonicalFileRoot,
       _rootStore = rootStore;

  final bool _isMacOS;
  final Future<ApplicationIdentity> Function() _resolveIdentity;
  final bool Function() _hasSignedApplicationIdentifier;
  final Uri? _canonicalFileRoot;
  final MacOSLoginKeychainRootStore? _rootStore;

  @override
  Future<ResolvedHost> resolve() async {
    if (!_isMacOS) {
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
      if (_hasSignedApplicationIdentifier()) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.unavailable,
        );
      }

      final accountHome = _canonicalFileRoot == null
          ? resolveMacOSAccountHome()
          : null;
      final root =
          _canonicalFileRoot ??
          _productionFileRoot(identity, accountHome: accountHome!);
      final binding = ResolvedApplicationBinding.derive(
        identity: identity,
        profile: _macOSUnentitledProfile,
        canonicalFileRoot: root,
      );
      final files = PosixStoreFiles(binding: binding, canonicalFileRoot: root);
      final roots =
          _rootStore ??
          AppleMacOSLoginKeychainRootStore(accountHome: accountHome!);
      final protector = MacOSLoginKeychainProtector(
        binding: binding,
        roots: roots,
      );
      return ResolvedHost(binding: binding, files: files, protector: protector);
    } on AppleHostApiFailure {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.unavailable,
      );
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

bool _currentProcessHasSignedApplicationIdentifier() =>
    AppleHostApi.macOS().macOSSignedApplicationIdentifierOrNull() != null;

Uri _productionFileRoot(
  ApplicationIdentity identity, {
  required String accountHome,
}) {
  // The readable prefix aids local diagnosis. The full lowercase digest keeps
  // distinct case-sensitive application IDs distinct on case-folding volumes.
  final digest = const DartSha256()
      .hashSync(
        utf8.encode(
          'keybay:v2:macos-unentitled:file-root\u0000'
          '${identity.assurance.wireCode}\u0000'
          '$macOSUnentitledProfileCode\u0000'
          '${identity.stableValue}',
        ),
      )
      .bytes;
  final suffix = digest
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return Uri.directory(
    '$accountHome/Library/Application Support/'
    '${identity.stableValue}-$suffix.keybay-v2',
  );
}
