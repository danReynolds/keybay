/// Internal platform-root boundary for Keybay V2.
library;

import 'dart:typed_data';

import 'device_access.dart';
import 'format/store_format.dart';
import 'host_binding.dart';

/// Immutable, bounded provider continuation state carried in the bootstrap.
///
/// The constructor snapshots [bytes], and [copyBytes] never exposes the owned
/// buffer. The persisted representation is bounded by
/// [V2StoreLimits.providerStateBytes].
final class ProviderState {
  /// Snapshots provider continuation bytes.
  ProviderState(List<int> bytes) : _bytes = _copyProviderState(bytes);

  final Uint8List _bytes;

  /// The number of opaque bytes.
  int get length => _bytes.length;

  /// Returns a fresh copy for a provider call or bootstrap serialization.
  Uint8List copyBytes() => Uint8List.fromList(_bytes);

  /// Compares two non-secret provider-state values without exposing buffers.
  bool hasSameBytes(ProviderState other) {
    if (length != other.length) return false;
    var difference = 0;
    for (var index = 0; index < length; index++) {
      difference |= _bytes[index] ^ other._bytes[index];
    }
    return difference == 0;
  }

  @override
  String toString() => 'ProviderState(length: $length)';
}

Uint8List _copyProviderState(List<int> bytes) {
  if (bytes.length > V2StoreLimits.providerStateBytes) {
    throw ArgumentError.value(
      bytes.length,
      'bytes',
      'provider state exceeds the V2 bound',
    );
  }
  for (final byte in bytes) {
    if (byte < 0 || byte > 0xff) {
      throw ArgumentError.value(
        '<redacted>',
        'bytes',
        'provider state must contain bytes',
      );
    }
  }
  return Uint8List.fromList(bytes);
}

/// Whether an operation may invoke trusted operating-system/provider UI.
///
/// Permission is fixed at acquisition and applies to the returned lease or
/// prepared reset until it closes. Allowed interaction is permission, not a
/// requirement; a provider may retain a stricter no-UI policy.
enum PlatformInteraction {
  /// No provider call may display UI. Fail before invoking an interface that
  /// cannot enforce this restriction.
  forbidden,

  /// Trusted operating-system/provider UI may participate in the operation.
  allowed,
}

/// How platform-root acquisition for initialization completed.
enum RootCreationDisposition {
  /// This call created new Keybay-managed provider state.
  created,

  /// A concurrent creator won with the same storage-domain binding.
  adopted,

  /// The provider owns a reusable root independently of Keybay store files.
  /// Its presence is normal for an absent store, including after reset; it
  /// must not be treated as abandoned Keybay-managed provider state.
  reused,
}

/// Stable internal failure classes emitted by a platform protector.
enum PlatformProtectorFailureCode {
  unavailable,
  busy,
  locked,
  interactionRequired,
  invalidated,
  stateConflict,
  authenticationFailed,

  /// A prepared provider reset could not complete after file revocation.
  resetIncomplete,
  operationFailed,
  leaseClosed,
}

/// A redacted internal platform-protector failure.
///
/// The store engine maps this internal code to the public Keybay error
/// taxonomy; provider exceptions and subprocess output never cross this seam.
final class PlatformProtectorFailure implements Exception {
  /// Creates a redacted boundary failure.
  const PlatformProtectorFailure(this.code);

  final PlatformProtectorFailureCode code;

  @override
  String toString() => 'PlatformProtectorFailure(${code.name})';
}

/// Operation-scoped access to one platform root or sealing capability.
///
/// Implementations snapshot their byte inputs. [close] is idempotent and
/// clears any exportable root material retained by the lease. Every operation
/// obeys the [PlatformInteraction] policy fixed when this lease was acquired.
abstract interface class PlatformRootLease {
  /// Final provider state. On open, this must exactly match the supplied state.
  ProviderState get providerState;

  /// Seals a key package while authenticating the exact caller-supplied AAD.
  ///
  /// On success, the returned mutable buffer is fresh and caller-owned. The
  /// implementation retains no alias. The common engine rejects a result
  /// outside `1..V2StoreLimits.sealedPackageBytes`. The opaque sealed package
  /// is public ciphertext and has no zeroization contract.
  Future<Uint8List> sealPackage({
    required Uint8List plaintext,
    required Uint8List aad,
  });

  /// Opens a key package only under the exact caller-supplied AAD.
  ///
  /// On success, the returned mutable buffer is fresh and caller-owned. The
  /// implementation retains no plaintext alias; the caller is responsible for
  /// clearing the returned bytes.
  Future<Uint8List> openPackage({
    required Uint8List sealedPackage,
    required Uint8List aad,
  });

  /// Releases provider resources and clears operation-lived root material.
  Future<void> close();
}

/// A successful root acquisition for initialization.
final class PlatformRootCreation {
  /// Creates a result whose provider state is already final.
  const PlatformRootCreation({required this.lease, required this.disposition});

  final PlatformRootLease lease;
  final RootCreationDisposition disposition;
}

/// A non-mutatingly prepared reset of one fixed platform-provider target.
///
/// Preparation completes every provider qualification and interaction check
/// before the common engine revokes the live store file. [commit] is legal only
/// after that file-revocation point. It may remove only the provider target
/// fixed by the owning [PlatformProtector]; persisted file data cannot redirect
/// it. Closing without committing leaves provider state unchanged.
///
/// Implementations either hold the provider operation stable until [close] or
/// revalidate the exact prepared target before mutation. [close] is idempotent.
/// The interaction policy chosen at preparation applies through [commit].
abstract interface class PreparedPlatformReset {
  /// Commits the already-prepared provider operation.
  ///
  /// The method is single-use. Because the common reset has already crossed
  /// its file-revocation point, every failure is
  /// [PlatformProtectorFailureCode.resetIncomplete].
  Future<void> commit();

  /// Releases preparation resources without mutating provider state.
  Future<void> close();
}

/// A prepared update to a platform protector's [KeybayDeviceAccess] policy.
///
/// Two execution shapes exist across platforms:
/// - **In-place update / cleanup** (Apple Data Protection Keychain attribute
///   update, or Android retired-alias cleanup): [replacementLease] is `null`.
///   [commit] applies and verifies the update without rewriting the vault file.
/// - **Key rotation** (Android 12+ Keystore, where key parameters are
///   immutable): [replacementLease] holds a freshly generated inactive-slot
///   key lease with the target policy. The common engine re-seals the vault's
///   key package under [replacementLease], atomically commits and verifies the
///   updated vault file, and then calls [commit] to remove the retired prior
///   key. If the transaction fails before replacing live (or live is
///   affirmatively verified to still hold the old provider state), the caller
///   invokes [abort] to remove the unused replacement key. [close] only
///   releases lease resources and never deletes a platform key.
abstract interface class PreparedPlatformDeviceAccessChange {
  /// Non-null when the platform requires rotating to a new root key and
  /// rewriting the vault's bootstrap and sealed key package.
  PlatformRootLease? get replacementLease;

  /// Finalizes the change.
  ///
  /// For in-place updates, applies and verifies the updated OS attribute (or
  /// deletes a leftover retired alias). For key rotations, called only after
  /// the replacement vault file has atomically replaced live and been verified,
  /// removing the retired key.
  Future<void> commit();

  /// Removes an unused replacement key after the caller has affirmatively
  /// confirmed the live store still references the original provider state.
  ///
  /// Idempotent; a no-op for in-place changes or once [commit] has run.
  Future<void> abort();

  /// Releases preparation and lease resources without deleting any platform
  /// key. Idempotent.
  Future<void> close();
}

/// The mandatory platform protection for one resolved storage domain.
///
/// The implementation is fixed when the host binding is resolved. It has no
/// provider selector or fallback method, and reset accepts no persisted token
/// or caller-selected target.
abstract interface class PlatformProtector {
  /// The complete identity/profile/domain committed into provider state.
  ResolvedApplicationBinding get binding;

  /// Opens existing provider state, or returns `null` when it is absent.
  ///
  /// A successful lease returns provider state byte-identical to [state]. A
  /// changed or rejected continuation value is invalidation, not permission to
  /// rotate it or try another provider. When [interaction] is forbidden, a
  /// provider that cannot enforce no UI throws
  /// [PlatformProtectorFailureCode.interactionRequired] (or `locked`) before
  /// requesting access. The returned lease preserves this policy.
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  });

  /// Acquires a root for initialization under [interaction] and [deviceAccess].
  ///
  /// Managed roots use create-only/adopt-winner semantics. Ambient provider
  /// roots return [RootCreationDisposition.reused] without claiming ownership.
  /// The returned lease exposes its final immutable provider state before the
  /// common engine constructs bootstrap AAD.
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
    KeybayDeviceAccess deviceAccess = KeybayDeviceAccess.whenUnlocked,
  });

  /// Prepares an update to [deviceAccess] for an authenticated live store
  /// holding [state], or returns `null` when no change is applicable or
  /// required (for example, desktop login keyrings or an already-matching
  /// policy).
  Future<PreparedPlatformDeviceAccessChange?> prepareDeviceAccessChange(
    ProviderState state, {
    required KeybayDeviceAccess deviceAccess,
    required PlatformInteraction interaction,
  });

  /// Non-mutatingly prepares this provider's fixed reset behavior.
  ///
  /// This performs every capability, state, and interaction check that may
  /// prevent reset. Every connected provider must guarantee that a committed
  /// reset permits safe later initialization. No provider state is mutated
  /// before a returned [PreparedPlatformReset] is committed.
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  });
}
