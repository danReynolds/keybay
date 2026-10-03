@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_passkey_backend.dart';
import 'support/v2_test_keybay.dart';

void main() {
  for (final suite in [v2PrimitiveSuite, v2MethodsSuite]) {
    test(
      'suite $suite over-budget prefix fails before package access',
      () async {
        final provider = TestPasskeyProvider();
        final env = V2TestKeybay(
          applicationId: 'dev.keybay.oversized-suite-$suite',
          keypassClient: provider.client,
        );
        addTearDown(() async {
          await env.dispose();
          provider.clear();
        });
        final credential = suite == v2MethodsSuite
            ? const PasskeyCredential.system(rpId: 'vault.example.com')
            : null;
        final session = await env.open();
        if (credential != null) await session.auth.add(credential);
        await session.close();
        final pin = (await env.files.openPinnedLive())!;
        final original = await pin.readExact(offset: 0, length: pin.length);
        await pin.close();
        final bootstrap = decodeBootstrap(
          Uint8List.sublistView(
            original,
            0,
            decodeBootstrapCoreLength(
                  Uint8List.sublistView(original, 0, v2BootstrapCoreFixedBytes),
                ) +
                v2BootstrapLengthBytes,
          ),
        );
        final oversized = Uint8List(
          V2StoreLimits.legacyStoreBytes +
              (suite == v2MethodsSuite ? bootstrap.sealedPackageLength : 0) +
              1,
        )..setRange(0, original.length, original);
        env.files.replaceLiveBytes(oversized);
        final ceremonies = provider.operationCount;
        await expectLater(
          env.open(credential: credential),
          throwsA(
            isA<KeybayException>().having(
              (error) => error.code,
              'code',
              KeybayErrorCode.limitExceeded,
            ),
          ),
        );
        expect(provider.operationCount, ceremonies);
        final reads = env.files.openedHandles.last.reads;
        expect(reads, hasLength(2));
        expect(reads.first.length, v2BootstrapCoreFixedBytes);
        expect(reads.last.length, encodeBootstrap(bootstrap).length);
        expect(env.files.activeHandleCount, 0);
      },
    );
  }

  test(
    'full record budget permits passkey counter growth but no extra payload',
    () async {
      final provider = TestPasskeyProvider();
      final env = V2TestKeybay(
        applicationId: 'dev.keybay.auth-headroom',
        keypassClient: provider.client,
      );
      addTearDown(() async {
        await env.dispose();
        provider.clear();
      });
      PasskeyCredential credential() => PasskeyCredential.system(
        rpId: 'vault.example.com',
        label: 'Capacity regression',
      );

      var session = await env.open();
      await session.auth.add(credential());
      addTearDown(() => session.close());
      // Enrollment checks repeatability twice. Reach a persisted one-digit
      // counter so the next unlock must enlarge authenticated metadata.
      expect((await _readState(env)).counter, 2);
      for (var counter = 3; counter <= 9; counter++) {
        await session.close();
        session = await env.open(credential: credential());
        expect((await _readState(env)).counter, counter);
      }

      final records = <String, Uint8List>{
        for (var index = 0; index < 16; index++)
          'capacity/${index.toString().padLeft(2, '0')}': Uint8List(0),
      };
      for (final entry in records.entries) {
        await session.setBytes(entry.key, entry.value);
      }
      final empty = await _readState(env);
      var remaining = V2StoreLimits.nonPackageStoreBytes - empty.nonPackage;
      var marker = 1;
      for (final key in records.keys) {
        final length = remaining > V2StoreLimits.recordValueBytes
            ? V2StoreLimits.recordValueBytes
            : remaining;
        final bytes = Uint8List(length)..fillRange(0, length, marker++);
        records[key] = bytes;
        await session.setBytes(key, bytes);
        remaining -= length;
      }
      expect(remaining, 0);
      final full = await _readState(env);
      expect(full.counter, 9);
      expect(full.nonPackage, V2StoreLimits.nonPackageStoreBytes);
      expect(full.length, greaterThan(V2StoreLimits.legacyStoreBytes));

      final last = records['capacity/15']!;
      expect(last.length, lessThan(V2StoreLimits.recordValueBytes));
      final generation = env.files.liveGeneration;
      await expectLater(
        session.setBytes('capacity/15', Uint8List.fromList([...last, 0x7f])),
        throwsA(
          isA<KeybayException>().having(
            (error) => error.code,
            'code',
            KeybayErrorCode.limitExceeded,
          ),
        ),
      );
      expect(env.files.liveGeneration, generation);
      expect(env.files.hasTransactionArtifacts, isFalse);

      await session.close();
      session = await env.open(credential: credential());
      final grown = await _readState(env);
      expect(grown.counter, 10);
      expect(grown.packageLength, full.packageLength + 1);
      expect(grown.length, full.length + 1);
      expect(grown.nonPackage, V2StoreLimits.nonPackageStoreBytes);
      expect(await session.listKeys(), records.keys.toList());
      expect(await session.getBytes('capacity/00'), records['capacity/00']);
      expect(await session.getBytes('capacity/15'), last);
      provider.expectReleased();
      expect(env.files.activeHandleCount, 0);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<_State> _readState(V2TestKeybay env) async {
  final pin = (await env.files.openPinnedLive())!;
  PlatformRootLease? lease;
  Uint8List? plaintext;
  V2KeyPackage? package;
  try {
    final fixed = await pin.readExact(
      offset: 0,
      length: v2BootstrapCoreFixedBytes,
    );
    final bootstrapLength =
        decodeBootstrapCoreLength(fixed) + v2BootstrapLengthBytes;
    final bootstrap = decodeBootstrap(
      await pin.readExact(offset: 0, length: bootstrapLength),
    );
    expect(bootstrap.core.suite, v2MethodsSuite);
    lease = (await env.protector.openExisting(
      ProviderState(bootstrap.core.providerState),
      interaction: PlatformInteraction.forbidden,
    ))!;
    plaintext = await lease.openPackage(
      sealedPackage: await pin.readExact(
        offset: bootstrapLength,
        length: bootstrap.sealedPackageLength,
      ),
      aad: encodePlatformPackageAad(
        storageDomain: env.binding.domain.copyBytes(),
        bootstrapCore: bootstrap.core,
      ),
    );
    package = decodeKeyPackage(plaintext);
    final method = (package as V2MethodsPackage).methods.single;
    final json =
        jsonDecode(utf8.decode(method.passkeyRecord)) as Map<String, dynamic>;
    return _State(
      pin.length,
      bootstrap.sealedPackageLength,
      json['signCount']! as int,
    );
  } finally {
    package?.clear();
    plaintext?.fillRange(0, plaintext.length, 0);
    await lease?.close();
    await pin.close();
  }
}

final class _State {
  const _State(this.length, this.packageLength, this.counter);

  final int length;
  final int packageLength;
  final int counter;
  int get nonPackage => length - packageLength;
}
