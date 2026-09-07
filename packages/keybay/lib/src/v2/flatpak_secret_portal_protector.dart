/// Package protection using Flatpak's retained, application-scoped portal secret.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'entropy_source.dart';
import 'exportable_root_lease.dart';
import 'host_binding.dart';
import 'linux_secret_portal.dart';
import 'platform_protector.dart';

/// Necessary size bound for the qualified 256-bit wrapping-root profile.
/// Length alone does not establish entropy; provider generation needs review.
const int flatpakMinimumSecretBytes = 32;

final class FlatpakSecretPortalProtector implements PlatformProtector {
  FlatpakSecretPortalProtector({
    required this.binding,
    required LinuxSecretPortal portal,
    V2EntropySource? entropy,
  }) : _portal = portal,
       _entropy = entropy;

  @override
  final ResolvedApplicationBinding binding;
  final LinuxSecretPortal _portal;
  final V2EntropySource? _entropy;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) async {
    // This profile supports no continuation token, including in a bootstrap.
    if (state.length != 0) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    return _acquire(interaction);
  }

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) async => PlatformRootCreation(
    lease: await _acquire(interaction),
    disposition: RootCreationDisposition.reused,
  );

  Future<PlatformRootLease> _acquire(PlatformInteraction interaction) async {
    if (interaction != PlatformInteraction.allowed) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.interactionRequired,
      );
    }
    final secret = await _portal.retrieveSecret(interaction: interaction);
    SecretKeyData? source;
    SecretKeyData? derived;
    Uint8List? root;
    try {
      // HKDF expands key material, not entropy. This profile deliberately
      // refuses short portal values even though the wire format is opaque.
      if (secret.length < flatpakMinimumSecretBytes ||
          secret.length > linuxSecretPortalMaxSecretBytes) {
        throw const PlatformProtectorFailure(
          PlatformProtectorFailureCode.operationFailed,
        );
      }
      source = SecretKeyData(secret, overwriteWhenDestroyed: true);
      derived =
          await const DartHkdf(
            hmac: DartHmac(DartSha256()),
            outputLength: 32,
          ).deriveKey(
            secretKey: source,
            nonce: binding.domain.copyBytes(),
            info: utf8.encode('keybay:v2:linux-flatpak:portal-root:v1'),
          );
      root = Uint8List.fromList(derived.bytes);
      return ExportableRootLease(
        root: root,
        providerState: ProviderState(const <int>[]),
        entropy: _entropy,
      );
    } on PlatformProtectorFailure {
      rethrow;
    } on Object {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    } finally {
      secret.fillRange(0, secret.length, 0);
      source?.destroy();
      derived?.destroy();
      if (root != null) root.fillRange(0, root.length, 0);
    }
  }

  /// Reset only revokes Keybay files. The portal provides no delete operation;
  /// retrieving its secret here would add interaction without changing reset.
  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) async => _RetainedPortalReset();
}

final class _RetainedPortalReset implements PreparedPlatformReset {
  bool _finished = false;

  @override
  Future<void> commit() async {
    if (_finished) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.resetIncomplete,
      );
    }
    _finished = true;
  }

  @override
  Future<void> close() async => _finished = true;
}
