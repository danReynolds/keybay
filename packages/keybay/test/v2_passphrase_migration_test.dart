@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2PassphraseDeriver, V2StoreEngine, V2StoreSession;
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_store_fixture.dart';

void main() {
  test('a legacy store at the full 16 MiB limit remains migratable', () async {
    final emptyRecords = <String, List<int>>{
      for (var index = 0; index < 16; index++)
        'capacity/${index.toString().padLeft(2, '0')}': const [],
    };
    final empty = await _LegacyFixture.create(records: emptyRecords);
    final emptyBytes = await empty.copyLive();
    final overhead = emptyBytes.length;
    _clear(emptyBytes);
    await empty.dispose();

    var remaining = V2StoreLimits.legacyStoreBytes - overhead;
    final records = <String, List<int>>{};
    var marker = 1;
    for (final key in emptyRecords.keys) {
      final length = remaining > V2StoreLimits.recordValueBytes
          ? V2StoreLimits.recordValueBytes
          : remaining;
      records[key] = Uint8List(length)..fillRange(0, length, marker++);
      remaining -= length;
    }
    expect(remaining, 0);
    final fixture = await _LegacyFixture.create(records: records);
    addTearDown(fixture.dispose);
    final original = await fixture.copyLive();
    addTearDown(() => _clear(original));
    expect(original.length, V2StoreLimits.legacyStoreBytes);
    final originalFrameDigest = (await const DartSha256().hash(
      _frames(original),
    )).bytes;

    final session = await fixture.engine.open(credential: fixture.credential());
    addTearDown(session.close);
    final upgraded = await fixture.copyLive();
    addTearDown(() => _clear(upgraded));
    expect(_bootstrap(upgraded).core.suite, v2MethodsSuite);
    expect(upgraded.length, V2StoreLimits.legacyStoreBytes + 63);
    expect(
      (await const DartSha256().hash(_frames(upgraded))).bytes,
      originalFrameDigest,
    );
    expect(await session.getBytes('capacity/00'), records['capacity/00']);
    expect(await session.getBytes('capacity/15'), records['capacity/15']);
    await session.close();

    final reopened = await fixture.newEngine().open(
      credential: fixture.credential(),
    );
    addTearDown(reopened.close);
    expect(await reopened.listKeys(), emptyRecords.keys.toList());
    expect(await reopened.getBytes('capacity/15'), records['capacity/15']);
    await reopened.delete('capacity/00');
    await reopened.close();
    final afterDelete = await fixture.newEngine().open(
      credential: fixture.credential(),
    );
    addTearDown(afterDelete.close);
    expect(await afterDelete.getBytes('capacity/00'), isNull);
    expect(await afterDelete.getBytes('capacity/15'), records['capacity/15']);
    expect(fixture.files.activeHandleCount, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'legacy passphrase open migrates once and preserves key, epoch, and data',
    () async {
      final fixture = await _LegacyFixture.create();
      addTearDown(fixture.dispose);
      final original = await fixture.copyLive();
      final originalPackage = await fixture.openPackage(original);
      expect(originalPackage, isA<V2PassphrasePackage>());
      expect(_bootstrap(original).core.suite, v2PrimitiveSuite);
      originalPackage.clear();
      var commits = 0;
      fixture.files.afterReplaceLive = () => commits++;

      final session = await fixture.engine.open(
        credential: fixture.credential(),
      );
      addTearDown(session.close);
      expect(session.wasInitialized, isFalse);
      await _expectRecords(session);
      expect(
        (await session.auth.list()).single.id,
        encodeMethodId(fixture.methodId),
      );
      final upgraded = await fixture.copyLive();
      try {
        await fixture.expectUpgraded(upgraded);
        expect(_frames(upgraded), _frames(original));
        expect(upgraded, isNot(equals(original)));
        expect(commits, 1);
        expect(fixture.files.hasTransactionArtifacts, isFalse);
        expect(fixture.files.activeHandleCount, 0);
        expect(fixture.deriver.allBorrowedBuffersCleared, isTrue);
        await session.close();

        // A fresh engine must unlock the new envelope using the same phrase.
        final reopened = await fixture.newEngine().open(
          credential: fixture.credential(),
        );
        addTearDown(reopened.close);
        await _expectRecords(reopened);
        expect(
          (await reopened.auth.list()).single.id,
          encodeMethodId(fixture.methodId),
        );
        expect(
          commits,
          1,
          reason: 'suite 2 opens must not repeat the migration',
        );
        expect(await fixture.copyLive(), upgraded);
      } finally {
        _clear(original);
        _clear(upgraded);
      }
    },
  );

  test(
    'wrong passphrase leaves legacy bytes and abandoned staging untouched',
    () async {
      final fixture = await _LegacyFixture.create();
      addTearDown(fixture.dispose);
      final before = await fixture.copyLive();
      final generation = fixture.files.liveGeneration;
      fixture.files.hasTransactionArtifacts = true;
      var stages = 0;
      fixture.files.beforeStageFinish = () => stages++;

      await _expectNoSession(
        fixture.engine.open(
          credential: PassphraseCredential(
            phrase: Uint8List.fromList([9, 9, 9]),
          ),
        ),
        KeybayErrorCode.unlockFailed,
      );
      expect(await fixture.copyLive(), before);
      expect(fixture.files.liveGeneration, generation);
      expect(fixture.files.hasTransactionArtifacts, isTrue);
      expect(stages, 0);
      expect(fixture.files.activeHandleCount, 0);
      expect(fixture.deriver.allBorrowedBuffersCleared, isTrue);

      final recovered = await fixture.engine.open(
        credential: fixture.credential(),
      );
      addTearDown(recovered.close);
      await _expectRecords(recovered);
      expect(fixture.files.hasTransactionArtifacts, isFalse);
      _clear(before);
    },
  );

  test(
    'corrupt legacy manifest fails authentication before any migration write',
    () async {
      final fixture = await _LegacyFixture.create();
      addTearDown(fixture.dispose);
      final corrupt = await fixture.copyLive();
      corrupt[_layout(corrupt).manifestOffset + V2StoreLimits.nonceBytes] ^= 1;
      fixture.files.replaceLiveBytes(corrupt);
      fixture.files.hasTransactionArtifacts = true;
      final generation = fixture.files.liveGeneration;
      var stages = 0;
      fixture.files.beforeStageFinish = () => stages++;

      await _expectNoSession(
        fixture.engine.open(credential: fixture.credential()),
        KeybayErrorCode.storeAuthenticationFailed,
      );
      expect(await fixture.copyLive(), corrupt);
      expect(fixture.files.liveGeneration, generation);
      expect(fixture.files.hasTransactionArtifacts, isTrue);
      expect(stages, 0);
      expect(fixture.files.activeHandleCount, 0);
      expect(fixture.deriver.allBorrowedBuffersCleared, isTrue);
      _clear(corrupt);
    },
  );

  for (final point in ['stage finish', 'before rename']) {
    test(
      'migration $point failure returns no session and preserves legacy store',
      () async {
        final fixture = await _LegacyFixture.create();
        addTearDown(fixture.dispose);
        final original = await fixture.copyLive();
        final generation = fixture.files.liveGeneration;
        var reached = 0;
        void fail() {
          reached++;
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        }

        if (point == 'stage finish') {
          fixture.files.beforeStageFinish = fail;
        } else {
          fixture.files.beforeReplaceLive = fail;
        }

        await _expectNoSession(
          fixture.engine.open(credential: fixture.credential()),
          KeybayErrorCode.storageOperationFailed,
        );
        expect(
          reached,
          1,
          reason: 'failure must reach the intended transaction boundary',
        );
        expect(await fixture.copyLive(), original);
        expect(fixture.files.liveGeneration, generation);
        expect(fixture.files.hasTransactionArtifacts, isFalse);
        expect(fixture.files.activeHandleCount, 0);
        expect(fixture.deriver.allBorrowedBuffersCleared, isTrue);
        fixture.files.beforeStageFinish = null;
        fixture.files.beforeReplaceLive = null;

        final retried = await fixture.engine.open(
          credential: fixture.credential(),
        );
        addTearDown(retried.close);
        await _expectRecords(retried);
        await fixture.expectUpgraded(await fixture.copyLive());
        _clear(original);
      },
    );
  }

  test('corrupt staged migration is rejected before rename', () async {
    final fixture = await _LegacyFixture.create();
    addTearDown(fixture.dispose);
    final original = await fixture.copyLive();
    final generation = fixture.files.liveGeneration;
    var reached = 0;
    fixture.files.beforeStageVerification = (bytes) {
      reached++;
      bytes[_layout(bytes).manifestOffset + V2StoreLimits.nonceBytes] ^= 1;
    };
    await _expectNoSession(
      fixture.engine.open(credential: fixture.credential()),
      KeybayErrorCode.storeAuthenticationFailed,
    );
    expect(reached, 1);
    expect(await fixture.copyLive(), original);
    expect(fixture.files.liveGeneration, generation);
    expect(fixture.files.hasTransactionArtifacts, isFalse);
    expect(fixture.files.activeHandleCount, 0);
    _clear(original);
  });

  test(
    'post-rename migration failure returns no session but leaves a recoverable upgrade',
    () async {
      final fixture = await _LegacyFixture.create();
      addTearDown(fixture.dispose);
      final original = await fixture.copyLive();
      final generation = fixture.files.liveGeneration;
      var reached = 0;
      fixture.files.afterReplaceLive = () {
        reached++;
        throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
      };
      await _expectNoSession(
        fixture.engine.open(credential: fixture.credential()),
        KeybayErrorCode.storageOperationFailed,
      );
      expect(reached, 1);
      expect(fixture.files.liveGeneration, isNot(generation));
      expect(fixture.files.hasTransactionArtifacts, isFalse);
      expect(fixture.files.activeHandleCount, 0);
      expect(fixture.deriver.allBorrowedBuffersCleared, isTrue);
      final committed = await fixture.copyLive();
      await fixture.expectUpgraded(committed);
      expect(_frames(committed), _frames(original));
      fixture.files.afterReplaceLive = null;

      final reopened = await fixture.newEngine().open(
        credential: fixture.credential(),
      );
      addTearDown(reopened.close);
      await _expectRecords(reopened);
      expect(await fixture.copyLive(), committed);
      _clear(original);
      _clear(committed);
    },
  );
}

Future<void> _expectNoSession(
  Future<V2StoreSession> operation,
  KeybayErrorCode code,
) async {
  V2StoreSession? published;
  try {
    await expectLater(
      operation.then((session) {
        published = session;
        return session;
      }),
      throwsA(
        isA<KeybayException>().having((error) => error.code, 'code', code),
      ),
    );
    expect(published, isNull);
  } finally {
    await published?.close();
  }
}

Future<void> _expectRecords(KeybaySession session) async {
  expect(await session.get('alpha/value'), 'retained alpha');
  expect(await session.get('zulu/value'), 'retained zulu');
}

/// Builds policy 1 directly; the current engine is never used to manufacture
/// the legacy generation. Only its expensive KDF is replaced with a test hash.
final class _LegacyFixture {
  _LegacyFixture._(this.base, this.deriver);

  static const int epoch = 7;
  final V2StoreFixture base;
  final _FastDeriver deriver;
  final Uint8List methodId = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x40 + i),
  );
  final Uint8List salt = Uint8List.fromList(
    List<int>.generate(16, (i) => 0x60 + i),
  );
  late final V2StoreEngine engine = newEngine();

  MemoryPinnedStoreFiles get files => base.files;

  PassphraseCredential credential() =>
      PassphraseCredential(phrase: Uint8List.fromList([1, 3, 3, 7]));

  V2StoreEngine newEngine() =>
      V2StoreEngine(base.hostPlatform, passphraseDeriver: deriver);

  static Future<_LegacyFixture> create({
    Map<String, List<int>>? records,
  }) async {
    final base = await buildV2StoreFixture(
      records:
          records ??
          {
            'alpha/value': utf8.encode('retained alpha'),
            'zulu/value': utf8.encode('retained zulu'),
          },
      epoch: epoch,
      applicationId: 'dev.keybay.legacy-passphrase-migration',
    );
    final fixture = _LegacyFixture._(base, _FastDeriver());
    final source = base.bytes;
    final bootstrap = _bootstrap(source);
    final layout = _layout(source);
    final storeKey = base.copyStoreKey();
    final storeId = base.storeId;
    final domain = base.host.binding.domain.copyBytes();
    final phrase = Uint8List.fromList([1, 3, 3, 7]);
    Uint8List? material;
    Uint8List? plaintext;
    V2KeyPackage? package;
    V2Manifest? manifest;
    PlatformRootLease? lease;
    var success = false;
    try {
      manifest = await openManifest(
        storeKey: storeKey,
        storeId: storeId,
        storageDomain: domain,
        bootstrap: bootstrap,
        sealedPackage: Uint8List.sublistView(
          source,
          layout.packageOffset,
          layout.frameRegionOffset,
        ),
        sealedManifest: Uint8List.sublistView(
          source,
          layout.manifestOffset,
          layout.trailerOffset,
        ),
      );
      material = await fixture.deriver.derive(
        passphrase: phrase,
        profileId: 1,
        salt: fixture.salt,
      );
      final inner = await sealPassphraseEnvelope(
        passphraseKey: material,
        storeKey: storeKey,
        storeId: storeId,
        epoch: epoch,
        methodId: fixture.methodId,
        profileId: 1,
        salt: fixture.salt,
        nonce: Uint8List.fromList(List<int>.filled(24, 0x77)),
      );
      package = V2PassphrasePackage(
        storeId: storeId,
        epoch: epoch,
        methodId: fixture.methodId,
        profileId: 1,
        salt: fixture.salt,
        innerEnvelope: inner,
      );
      _clear(inner);
      plaintext = encodeKeyPackage(package);
      lease = await base.host.protector.openExisting(
        ProviderState(bootstrap.core.providerState),
        interaction: PlatformInteraction.forbidden,
      );
      if (lease == null) throw StateError('The fixture root disappeared.');
      final sealed = await lease.sealPackage(
        plaintext: plaintext,
        aad: encodePlatformPackageAad(
          storageDomain: domain,
          bootstrapCore: bootstrap.core,
        ),
      );
      final legacyBootstrap = V2Bootstrap(
        core: bootstrap.core,
        sealedPackageLength: sealed.length,
      );
      final sealedManifest = await sealManifest(
        storeKey: storeKey,
        storeId: storeId,
        storageDomain: domain,
        bootstrap: legacyBootstrap,
        sealedPackage: sealed,
        manifest: manifest,
        nonce: Uint8List.fromList(List<int>.filled(24, 0x88)),
      );
      final bytes =
          (BytesBuilder()
                ..add(encodeBootstrap(legacyBootstrap))
                ..add(sealed)
                ..add(
                  Uint8List.sublistView(
                    source,
                    layout.frameRegionOffset,
                    layout.manifestOffset,
                  ),
                )
                ..add(sealedManifest)
                ..add(encodeManifestLength(sealedManifest.length)))
              .takeBytes();
      fixture.files.replaceLiveBytes(bytes);
      _clear(bytes);
      success = true;
      return fixture;
    } finally {
      await lease?.close();
      manifest?.clear();
      package?.clear();
      if (material != null) _clear(material);
      if (plaintext != null) _clear(plaintext);
      for (final bytes in [source, storeKey, storeId, domain, phrase]) {
        _clear(bytes);
      }
      if (!success) await fixture.dispose();
    }
  }

  Future<Uint8List> copyLive() async {
    final pin = await files.openPinnedLive();
    if (pin == null) throw StateError('No live fixture.');
    try {
      return await pin.readExact(offset: 0, length: pin.length);
    } finally {
      await pin.close();
    }
  }

  Future<V2KeyPackage> openPackage(Uint8List bytes) async {
    final bootstrap = _bootstrap(bytes);
    final layout = _layout(bytes);
    final lease = await base.host.protector.openExisting(
      ProviderState(bootstrap.core.providerState),
      interaction: PlatformInteraction.forbidden,
    );
    if (lease == null) throw StateError('The fixture root disappeared.');
    Uint8List? plaintext;
    try {
      plaintext = await lease.openPackage(
        sealedPackage: Uint8List.sublistView(
          bytes,
          layout.packageOffset,
          layout.frameRegionOffset,
        ),
        aad: encodePlatformPackageAad(
          storageDomain: base.host.binding.domain.copyBytes(),
          bootstrapCore: bootstrap.core,
        ),
      );
      return decodeKeyPackage(plaintext);
    } finally {
      if (plaintext != null) _clear(plaintext);
      await lease.close();
    }
  }

  Future<void> expectUpgraded(Uint8List bytes) async {
    final bootstrap = _bootstrap(bytes);
    final layout = _layout(bytes);
    final package = await openPackage(bytes);
    final originalKey = base.copyStoreKey();
    V2Manifest? manifest;
    try {
      expect(bootstrap.core.suite, v2MethodsSuite);
      expect(package, isA<V2MethodsPackage>());
      final methods = package as V2MethodsPackage;
      expect(methods.epoch, epoch);
      expect(methods.storeId, base.storeId);
      expect(methods.methods, hasLength(1));
      expect(methods.methods.single.kind, V2AuthMethodKind.passphrase);
      expect(methods.methods.single.methodId, methodId);
      expect(methods.methods.single.salt, salt);
      // The new manifest must still authenticate with the ORIGINAL Kstore.
      manifest = await openManifest(
        storeKey: originalKey,
        storeId: base.storeId,
        storageDomain: base.host.binding.domain.copyBytes(),
        bootstrap: bootstrap,
        sealedPackage: Uint8List.sublistView(
          bytes,
          layout.packageOffset,
          layout.frameRegionOffset,
        ),
        sealedManifest: Uint8List.sublistView(
          bytes,
          layout.manifestOffset,
          layout.trailerOffset,
        ),
      );
      expect(manifest.entries, hasLength(2));
    } finally {
      package.clear();
      manifest?.clear();
      _clear(originalKey);
    }
  }

  Future<void> dispose() async {
    files.beforeStageFinish = null;
    files.beforeStageVerification = null;
    files.beforeReplaceLive = null;
    files.afterReplaceLive = null;
    await base.dispose();
  }
}

/// Lifecycle-only derivation; the envelope and store authentication are real.
final class _FastDeriver implements V2PassphraseDeriver {
  final List<Uint8List> _borrowedInputs = [];
  final List<Uint8List> _returnedMaterial = [];

  bool get allBorrowedBuffersCleared => [
    ..._borrowedInputs,
    ..._returnedMaterial,
  ].every((bytes) => bytes.every((byte) => byte == 0));

  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) async {
    if (profileId != 1) throw StateError('Unexpected test KDF profile.');
    _borrowedInputs.add(passphrase);
    final input = Uint8List.fromList([profileId, ...passphrase, ...salt]);
    try {
      final material = Uint8List.fromList(
        const DartSha256().hashSync(input).bytes,
      );
      _returnedMaterial.add(material);
      return material;
    } finally {
      _clear(input);
    }
  }
}

V2Bootstrap _bootstrap(Uint8List bytes) {
  final coreLength = decodeBootstrapCoreLength(
    Uint8List.sublistView(bytes, 0, v2BootstrapCoreFixedBytes),
  );
  return decodeBootstrap(
    Uint8List.sublistView(bytes, 0, coreLength + v2BootstrapLengthBytes),
  );
}

V2StoreLayout _layout(Uint8List bytes) => deriveStoreLayout(
  fileLength: bytes.length,
  bootstrap: _bootstrap(bytes),
  sealedManifestLength: decodeManifestLength(
    Uint8List.sublistView(bytes, bytes.length - 4),
  ),
);

Uint8List _frames(Uint8List bytes) {
  final layout = _layout(bytes);
  return Uint8List.sublistView(
    bytes,
    layout.frameRegionOffset,
    layout.manifestOffset,
  );
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
