@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/entropy_source.dart';
import 'package:keybay/src/v2/exportable_root_lease.dart';
import 'package:keybay/src/v2/flatpak_host_platform.dart';
import 'package:keybay/src/v2/flatpak_secret_portal_protector.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/linux_secret_portal.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

void main() {
  test('wrapping root matches independent HKDF-SHA256 reference', () async {
    final portal = _Portal();
    final protector = _protector(portal);
    final creation = await protector.createOnly(
      interaction: PlatformInteraction.allowed,
    );
    expect(creation.disposition, RootCreationDisposition.reused);
    expect(creation.lease.providerState.length, 0);
    // Python stdlib hashlib/hmac RFC5869 extract+expand over:
    // IKM=01..40, salt=the framed storage-domain commitment for _binding(),
    // info=UTF8("keybay:v2:linux-flatpak:portal-root:v1"), L=32.
    final reference = ExportableRootLease(
      root: _hex(
        'c96f183ae552611287949b595f85080a068fba89925d6a90b011be1675c8b70a',
      ),
      providerState: ProviderState(const []),
      entropy: _FixedEntropy(),
    );
    try {
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final aad = Uint8List.fromList([4, 5, 6]);
      final sealed = await creation.lease.sealPackage(
        plaintext: plaintext,
        aad: aad,
      );
      expect(
        await reference.openPackage(sealedPackage: sealed, aad: aad),
        plaintext,
      );
      expect(portal.returned.single.every((byte) => byte == 0), isTrue);
    } finally {
      await creation.lease.close();
      await reference.close();
    }
  });

  test(
    'application and storage domain separate the same ambient secret',
    () async {
      final first = await _protector(
        _Portal(),
      ).createOnly(interaction: PlatformInteraction.allowed);
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final aad = Uint8List.fromList([4, 5, 6]);
      try {
        final sealed = await first.lease.sealPackage(
          plaintext: plaintext,
          aad: aad,
        );
        for (final binding in [
          _binding(application: 'org.example.Other'),
          _binding(root: 'file:///test/other/'),
        ]) {
          final other = await FlatpakSecretPortalProtector(
            binding: binding,
            portal: _Portal(),
          ).createOnly(interaction: PlatformInteraction.allowed);
          try {
            await expectLater(
              other.lease.openPackage(sealedPackage: sealed, aad: aad),
              throwsA(
                _failure(PlatformProtectorFailureCode.authenticationFailed),
              ),
            );
          } finally {
            await other.lease.close();
          }
        }
      } finally {
        await first.lease.close();
      }
    },
  );

  test(
    'forbidden interaction and nonempty state never retrieve a secret',
    () async {
      final portal = _Portal();
      final protector = _protector(portal);
      await expectLater(
        protector.createOnly(interaction: PlatformInteraction.forbidden),
        throwsA(_failure(PlatformProtectorFailureCode.interactionRequired)),
      );
      await expectLater(
        protector.openExisting(
          ProviderState(const []),
          interaction: PlatformInteraction.forbidden,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.interactionRequired)),
      );
      await expectLater(
        protector.openExisting(
          ProviderState(const [1]),
          interaction: PlatformInteraction.allowed,
        ),
        throwsA(_failure(PlatformProtectorFailureCode.invalidated)),
      );
      expect(portal.calls, 0);
    },
  );

  test('malformed portal material is cleared and rejected', () async {
    for (final length in [0, 1, 16, 31, 4097]) {
      final portal = _Portal(length: length);
      await expectLater(
        _protector(portal).createOnly(interaction: PlatformInteraction.allowed),
        throwsA(_failure(PlatformProtectorFailureCode.operationFailed)),
      );
      expect(portal.returned.single.every((byte) => byte == 0), isTrue);
    }
  });

  test('supports the minimum qualified secret size', () async {
    final portal = _Portal(length: 32);
    final creation = await _protector(
      portal,
    ).createOnly(interaction: PlatformInteraction.allowed);
    await creation.lease.close();
    expect(portal.returned.single.every((byte) => byte == 0), isTrue);
  });

  test('reset has no provider effects and preparation is single-use', () async {
    final portal = _Portal();
    final protector = _protector(portal);
    final preparation = await protector.prepareReset(
      interaction: PlatformInteraction.forbidden,
    );
    await preparation.commit();
    await expectLater(
      preparation.commit(),
      throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
    );
    await preparation.close();
    await preparation.close();
    final abandoned = await protector.prepareReset(
      interaction: PlatformInteraction.allowed,
    );
    await abandoned.close();
    await expectLater(
      abandoned.commit(),
      throwsA(_failure(PlatformProtectorFailureCode.resetIncomplete)),
    );
    expect(portal.calls, 0);
  });
}

FlatpakSecretPortalProtector _protector(_Portal portal) =>
    FlatpakSecretPortalProtector(
      binding: _binding(),
      portal: portal,
      entropy: _FixedEntropy(),
    );

ResolvedApplicationBinding _binding({
  String application = 'org.example.App',
  String root = 'file:///test/flatpak/',
}) => ResolvedApplicationBinding.derive(
  identity: ApplicationIdentity(
    stableValue: application,
    source: ApplicationIdentitySource.test,
    assurance: ApplicationIdentityAssurance.osEnforced,
  ),
  profile: HostProfile(flatpakProfileCode),
  canonicalFileRoot: Uri.parse(root),
);

Matcher _failure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having((e) => e.code, 'code', code);

Uint8List _hex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);

final class _Portal implements LinuxSecretPortal {
  _Portal({this.length = 64});
  final int length;
  int calls = 0;
  final List<Uint8List> returned = [];
  @override
  Future<Uint8List> retrieveSecret({
    required PlatformInteraction interaction,
  }) async {
    calls++;
    final value = Uint8List.fromList(
      List.generate(length, (index) => (index + 1) & 255),
    );
    returned.add(value);
    return value;
  }
}

final class _FixedEntropy implements V2EntropySource {
  @override
  Uint8List randomBytes(int length) => Uint8List(length);
}
