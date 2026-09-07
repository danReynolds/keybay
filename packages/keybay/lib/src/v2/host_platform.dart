/// Internal resolved-host boundary for Keybay V2.
library;

import 'application_identity.dart';
import 'host_binding.dart';
import 'platform_protector.dart';
import 'store_files.dart';

export 'application_identity.dart'
    show ApplicationIdentity, ApplicationIdentityAssurance;
export 'host_binding.dart' show HostProfile, ResolvedApplicationBinding;

/// The complete immutable binding consumed by the common store engine.
final class ResolvedHost {
  /// Binds one already-resolved identity/profile/domain to both adapters.
  ///
  /// A domain mismatch is an internal construction error. Persisted bytes are
  /// never an input to this constructor and therefore cannot redirect any of
  /// its targets.
  factory ResolvedHost({
    required ResolvedApplicationBinding binding,
    required StoreFiles files,
    required PlatformProtector protector,
  }) {
    if (!identical(files.binding, binding) ||
        !identical(protector.binding, binding)) {
      throw ArgumentError(
        'StoreFiles and PlatformProtector must share the resolved binding.',
      );
    }
    return ResolvedHost._(binding: binding, files: files, protector: protector);
  }

  const ResolvedHost._({
    required this.binding,
    required this.files,
    required this.protector,
  });

  final ResolvedApplicationBinding binding;
  ApplicationIdentity get identity => binding.identity;
  HostProfile get profile => binding.profile;
  final StoreFiles files;
  final PlatformProtector protector;
}

/// Resolves one complete host binding without consulting store metadata.
abstract interface class HostPlatform {
  Future<ResolvedHost> resolve();
}

/// Fails host resolution when no qualified platform profile exists.
final class UnsupportedHostPlatform implements HostPlatform {
  const UnsupportedHostPlatform();

  @override
  Future<ResolvedHost> resolve() => Future.error(
    const PlatformProtectorFailure(PlatformProtectorFailureCode.unavailable),
  );
}
