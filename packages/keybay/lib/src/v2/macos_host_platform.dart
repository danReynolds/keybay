/// Deterministic production dispatch between the two complete macOS profiles.
library;

import 'dart:io';

import '../ffi/apple_host.dart';
import 'apple_data_protection_host_platform.dart';
import 'application_identity.dart';
import 'host_platform.dart';
import 'macos_unentitled_host_platform.dart';
import 'platform_protector.dart';

/// Selects the entitled profile when the running process has a signed
/// application identifier, and the unentitled profile only when that
/// entitlement and any keychain access groups are genuinely absent.
///
/// Selection is not fallback. A probe error or any failure from the selected
/// profile is returned to the caller without trying the other profile.
final class MacOSHostPlatform implements HostPlatform {
  MacOSHostPlatform()
    : _isMacOS = Platform.isMacOS,
      _signedApplicationIdentifier = _currentSignedApplicationIdentifier,
      _entitled = MacOSEntitledHostPlatform(),
      _unentitled = MacOSUnentitledHostPlatform();

  MacOSHostPlatform.test({
    required String? Function() signedApplicationIdentifier,
    required HostPlatform entitled,
    required HostPlatform unentitled,
    bool isMacOS = true,
  }) : _isMacOS = isMacOS,
       _signedApplicationIdentifier = signedApplicationIdentifier,
       _entitled = entitled,
       _unentitled = unentitled;

  final bool _isMacOS;
  final String? Function() _signedApplicationIdentifier;
  final HostPlatform _entitled;
  final HostPlatform _unentitled;

  @override
  Future<ResolvedHost> resolve() async {
    if (!_isMacOS) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }

    final String? applicationIdentifier;
    try {
      applicationIdentifier = _signedApplicationIdentifier();
    } on ApplicationIdentityFailure {
      rethrow;
    } on Object {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.unavailable,
      );
    }

    return (applicationIdentifier == null ? _unentitled : _entitled).resolve();
  }
}

String? _currentSignedApplicationIdentifier() =>
    AppleHostApi.macOS().macOSSignedApplicationIdentifierOrNull();
