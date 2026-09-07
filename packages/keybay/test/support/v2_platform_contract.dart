import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

/// Isolated provider backing shared by every instance created within one test.
typedef PlatformProtectorFixture = ({
  PlatformProtector Function() newInstance,
  Future<void> Function() dispose,
});

/// Creates a fresh fixture so contract cases cannot share provider state.
typedef PlatformProtectorFixtureFactory =
    FutureOr<PlatformProtectorFixture> Function();

/// Runs the common contract for a provider whose root can be removed by reset.
/// Acquisitions permit interaction; each provider separately tests whether and
/// how it can reject interaction-forbidden requests without native UI.
void runDisposablePlatformProtectorContract({
  required String name,
  required PlatformProtectorFixtureFactory createFixture,
}) {
  group('$name disposable platform protector contract', () {
    late PlatformProtectorFixture fixture;
    late PlatformProtector protector;

    setUp(() async {
      fixture = await createFixture();
      protector = fixture.newInstance();
    });

    tearDown(() => fixture.dispose());

    test(
      'creates stable provider state, snapshots inputs, and binds AAD',
      () async {
        final creation = await protector.createOnly(
          interaction: PlatformInteraction.allowed,
        );
        expect(creation.disposition, RootCreationDisposition.created);
        final initialState = ProviderState(
          creation.lease.providerState.copyBytes(),
        );

        final expectedPlaintext = Uint8List.fromList([1, 2, 3]);
        final expectedAad = Uint8List.fromList([4, 5, 6]);
        final plaintext = Uint8List.fromList(expectedPlaintext);
        final sealAad = Uint8List.fromList(expectedAad);
        final sealing = creation.lease.sealPackage(
          plaintext: plaintext,
          aad: sealAad,
        );
        plaintext.fillRange(0, plaintext.length, 9);
        sealAad.fillRange(0, sealAad.length, 9);
        final sealed = await sealing;
        expect(identical(sealed, plaintext), isFalse);
        expect(identical(sealed, sealAad), isFalse);
        expect(
          sealed.length,
          inInclusiveRange(1, V2StoreLimits.sealedPackageBytes),
        );
        final sealedSnapshot = Uint8List.fromList(sealed);
        final independentlySealed = await creation.lease.sealPackage(
          plaintext: Uint8List.fromList(expectedPlaintext),
          aad: Uint8List.fromList(expectedAad),
        );
        expect(
          independentlySealed.length,
          inInclusiveRange(1, V2StoreLimits.sealedPackageBytes),
        );
        expect(identical(sealed, independentlySealed), isFalse);
        expect(sealed, sealedSnapshot);
        final independentSnapshot = Uint8List.fromList(independentlySealed);
        sealed[0] ^= 0xff;
        expect(independentlySealed, independentSnapshot);
        sealed[0] ^= 0xff;
        expect(
          await creation.lease.openPackage(
            sealedPackage: independentlySealed,
            aad: Uint8List.fromList(expectedAad),
          ),
          expectedPlaintext,
        );
        expect(creation.lease.providerState.hasSameBytes(initialState), isTrue);

        final sealedInput = Uint8List.fromList(sealed);
        final openAad = Uint8List.fromList(expectedAad);
        final opening = creation.lease.openPackage(
          sealedPackage: sealedInput,
          aad: openAad,
        );
        sealedInput.fillRange(0, sealedInput.length, 0);
        openAad.fillRange(0, openAad.length, 0);
        expect(await opening, expectedPlaintext);
        expect(creation.lease.providerState.hasSameBytes(initialState), isTrue);
        await expectLater(
          creation.lease.openPackage(
            sealedPackage: sealed,
            aad: Uint8List.fromList([4, 5, 7]),
          ),
          throwsA(
            _protectorFailure(
              PlatformProtectorFailureCode.authenticationFailed,
            ),
          ),
        );
        await creation.lease.close();
      },
    );

    test('rejects suffix bytes after a valid sealed key package', () async {
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      final package = V2PlatformOnlyPackage(
        storeId: List<int>.generate(
          V2StoreLimits.storeIdBytes,
          (index) => index,
        ),
        epoch: 1,
        storeKey: List<int>.generate(
          V2StoreLimits.storeKeyBytes,
          (index) => 0x20 + index,
        ),
      );
      final plaintext = encodeKeyPackage(package);
      package.clear();
      final aad = Uint8List.fromList(<int>[4, 5, 6]);
      final sealing = creation.lease.sealPackage(
        plaintext: plaintext,
        aad: aad,
      );
      plaintext.fillRange(0, plaintext.length, 0);
      final sealed = await sealing;
      final suffixed = Uint8List.fromList(<int>[...sealed, 0xa5]);

      await expectLater(
        creation.lease.openPackage(sealedPackage: suffixed, aad: aad),
        throwsA(
          _protectorFailure(PlatformProtectorFailureCode.authenticationFailed),
        ),
      );
      await creation.lease.close();
    });

    test('open returns byte-identical state and rejects replacement', () async {
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      final state = ProviderState(creation.lease.providerState.copyBytes());
      await creation.lease.close();

      final opened = await fixture.newInstance().openExisting(
        state,
        interaction: PlatformInteraction.allowed,
      );
      expect(opened, isNotNull);
      expect(opened!.providerState.hasSameBytes(state), isTrue);
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final aad = Uint8List.fromList([4, 5, 6]);
      final sealed = await opened.sealPackage(plaintext: plaintext, aad: aad);
      expect(opened.providerState.hasSameBytes(state), isTrue);
      expect(
        await opened.openPackage(sealedPackage: sealed, aad: aad),
        plaintext,
      );
      expect(opened.providerState.hasSameBytes(state), isTrue);
      await opened.close();

      await expectLater(
        protector.openExisting(
          _differentProviderState(state),
          interaction: PlatformInteraction.allowed,
        ),
        throwsA(_protectorFailure(PlatformProtectorFailureCode.invalidated)),
      );
    });

    test('caller mutation cannot alter owned provider state', () async {
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      final state = creation.lease.providerState;
      final exposedCopy = state.copyBytes();
      if (exposedCopy.isNotEmpty) {
        exposedCopy[0] ^= 0xff;
        expect(state.hasSameBytes(ProviderState(exposedCopy)), isFalse);
      }
      expect(identical(exposedCopy, state.copyBytes()), isFalse);

      final opened = await protector.openExisting(
        state,
        interaction: PlatformInteraction.allowed,
      );
      expect(opened, isNotNull);
      await opened!.close();
      await creation.lease.close();
    });

    test('same-domain create adopts and reset is fixed', () async {
      final first = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final aad = Uint8List.fromList([4, 5, 6]);
      final sealed = await first.lease.sealPackage(
        plaintext: plaintext,
        aad: aad,
      );
      final firstState = ProviderState(first.lease.providerState.copyBytes());
      await first.lease.close();

      final reopenedProtector = fixture.newInstance();
      final second = await reopenedProtector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      expect(second.disposition, RootCreationDisposition.adopted);
      expect(second.lease.providerState.hasSameBytes(firstState), isTrue);
      expect(
        await second.lease.openPackage(sealedPackage: sealed, aad: aad),
        plaintext,
      );
      await second.lease.close();

      await _commitReset(reopenedProtector);
      expect(
        await reopenedProtector.openExisting(
          firstState,
          interaction: PlatformInteraction.allowed,
        ),
        isNull,
      );
      await _commitReset(protector);
      expect(
        await protector.openExisting(
          firstState,
          interaction: PlatformInteraction.allowed,
        ),
        isNull,
      );
    });

    test('reset preparation is non-mutating and close aborts it', () async {
      final creation = await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      );
      final state = ProviderState(creation.lease.providerState.copyBytes());
      await creation.lease.close();

      final preparation = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );
      await preparation.close();
      await preparation.close();

      final opened = await protector.openExisting(
        state,
        interaction: PlatformInteraction.allowed,
      );
      expect(opened, isNotNull);
      await opened!.close();

      final committed = await protector.prepareReset(
        interaction: PlatformInteraction.allowed,
      );
      await committed.commit();
      await expectLater(
        committed.commit(),
        throwsA(
          _protectorFailure(PlatformProtectorFailureCode.resetIncomplete),
        ),
      );
      await committed.close();
      expect(
        await protector.openExisting(
          state,
          interaction: PlatformInteraction.allowed,
        ),
        isNull,
      );
    });

    test('closed leases cannot seal or open', () async {
      final lease = (await protector.createOnly(
        interaction: PlatformInteraction.allowed,
      )).lease;
      await lease.close();
      await lease.close();
      await expectLater(
        lease.sealPackage(plaintext: Uint8List(0), aad: Uint8List(0)),
        throwsA(_protectorFailure(PlatformProtectorFailureCode.leaseClosed)),
      );
      await expectLater(
        lease.openPackage(sealedPackage: Uint8List(0), aad: Uint8List(0)),
        throwsA(_protectorFailure(PlatformProtectorFailureCode.leaseClosed)),
      );
    });
  });
}

Future<void> _commitReset(PlatformProtector protector) async {
  final preparation = await protector.prepareReset(
    interaction: PlatformInteraction.allowed,
  );
  try {
    await preparation.commit();
  } finally {
    await preparation.close();
  }
}

ProviderState _differentProviderState(ProviderState state) {
  final bytes = state.copyBytes();
  if (bytes.isEmpty) return ProviderState([0]);
  bytes[0] ^= 0xff;
  return ProviderState(bytes);
}

Matcher _protectorFailure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );
