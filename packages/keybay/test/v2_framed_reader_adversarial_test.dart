@Tags(['unit'])
library;

import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_fakes.dart';
import 'support/v2_store_fixture.dart';

void main() {
  group('M4 outer structure', () {
    test(
      'rejects fixed-prefix and trailer lengths before oversized reads',
      () async {
        final fixture = await _fixture(1, <String, List<int>>{
          'service/a': <int>[1],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final hostilePrefix = fixture.bytes;
          ByteData.sublistView(
            hostilePrefix,
          ).setUint32(6, V2StoreLimits.providerStateBytes + 1);
          fixture.files.replaceLiveBytes(hostilePrefix);
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.limitExceeded)),
          );
          final prefixReads = fixture.files.openedHandles.last.reads;
          expect(prefixReads, hasLength(1));
          expect(prefixReads.single.length, v2BootstrapCoreFixedBytes);

          final hostileTrailer = fixture.bytes;
          ByteData.sublistView(hostileTrailer).setUint32(
            fixture.trailerOffset,
            V2StoreLimits.sealedManifestBytes + 1,
          );
          fixture.files.replaceLiveBytes(hostileTrailer);
          final readsBefore = fixture.files.reads.length;
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.limitExceeded)),
          );
          final trailerReads = fixture.files.reads.skip(readsBefore);
          expect(
            trailerReads.every((read) => read.length <= fixture.packageLength),
            isTrue,
          );
        } finally {
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test(
      'rejects truncation, a trailing frame byte, and a tiny file',
      () async {
        final fixture = await _fixture(2, <String, List<int>>{
          'service/a': <int>[1, 2, 3],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final frame = fixture.frames['service/a']!;
          final truncated = _removeRange(fixture.bytes, frame.offset, 1);
          fixture.files.replaceLiveBytes(truncated);
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );

          final trailingFrameByte = _insertRange(
            fixture.bytes,
            fixture.manifestOffset,
            const <int>[0xaa],
          );
          fixture.files.replaceLiveBytes(trailingFrameByte);
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );

          fixture.files.replaceLiveBytes(Uint8List(20));
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.limitExceeded)),
          );
          expect(fixture.files.activeHandleCount, 0);
        } finally {
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test('invalid length keeps precedence when pin cleanup fails', () async {
      final fixture = await _fixture(17, <String, List<int>>{
        'service/a': <int>[1],
      });
      fixture.files.replaceLiveBytes(Uint8List(20));
      fixture.files.closeFailure = const StoreFilesFailure(
        StoreFilesFailureCode.operationFailed,
      );
      try {
        await expectLater(
          V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
          throwsA(_failure(KeybayErrorCode.limitExceeded)),
        );
        expect(fixture.files.closedHandleCount, 1);
        expect(fixture.files.activeHandleCount, 0);
      } finally {
        fixture.files.closeFailure = null;
        await fixture.dispose();
      }
    });
  });

  group('M4 authentication boundaries', () {
    test('rejects a mutated platform-sealed package during open', () async {
      final fixture = await _fixture(3, <String, List<int>>{
        'service/a': <int>[1],
      });
      try {
        final bytes = fixture.bytes
          ..[fixture.packageOffset + fixture.packageLength ~/ 2] ^= 1;
        fixture.files.replaceLiveBytes(bytes);
        await expectLater(
          V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
          throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
        );
        expect(fixture.files.activeHandleCount, 0);
      } finally {
        await fixture.dispose();
      }
    });

    test(
      'binds record reads to exact bootstrap, package, and manifest bytes',
      () async {
        final fixture = await _fixture(4, <String, List<int>>{
          'service/a': <int>[1],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final bootstrap = fixture.bytes..[v2BootstrapCoreFixedBytes] ^= 1;
          fixture.files.replaceLiveBytes(bootstrap);
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );

          final package = fixture.bytes..[fixture.packageOffset] ^= 1;
          fixture.files.replaceLiveBytes(package);
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );

          final manifest = fixture.bytes..[fixture.manifestOffset] ^= 1;
          fixture.files.replaceLiveBytes(manifest);
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );
        } finally {
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test(
      'rejects an authenticated manifest whose lengths do not consume frames',
      () async {
        const seed = 5;
        final fixture = await _fixture(seed, <String, List<int>>{
          'service/a': <int>[1, 2, 3],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        final storeKey = _storeKey(seed);
        try {
          final bytes = fixture.bytes;
          final frame = fixture.frames['service/a']!;
          final frameBytes = Uint8List.sublistView(
            bytes,
            frame.offset,
            frame.offset + frame.length,
          );
          final digest = digestFrame(frameBytes);
          final invalidManifest = V2Manifest(<V2ManifestEntry>[
            V2ManifestEntry(
              key: 'service/a',
              frameLength: frame.length + 1,
              frameDigest: digest,
            ),
          ]);
          final sealed = await _sealFixtureManifest(
            fixture: fixture,
            storeBytes: bytes,
            storeKey: storeKey,
            manifest: invalidManifest,
            nonceMarker: 0x91,
          );
          try {
            expect(sealed.length, fixture.manifestLength);
            bytes.setRange(
              fixture.manifestOffset,
              fixture.manifestOffset + sealed.length,
              sealed,
            );
            fixture.files.replaceLiveBytes(bytes);
          } finally {
            _clear(sealed);
            invalidManifest.clear();
            _clear(digest);
          }

          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );
        } finally {
          _clear(storeKey);
          await session.close();
          await fixture.dispose();
        }
      },
    );
  });

  group('M4 selected frames', () {
    test(
      'rejects a selected frame digest mismatch before releasing it',
      () async {
        final fixture = await _fixture(6, <String, List<int>>{
          'service/a': <int>[1, 2, 3],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final frame = fixture.frames['service/a']!;
          final bytes = fixture.bytes..[frame.offset + 24] ^= 1;
          fixture.files.replaceLiveBytes(bytes);
          await expectLater(
            session.getBytes('service/a'),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );
        } finally {
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test('a recomputed digest never substitutes for frame AEAD', () async {
      const seed = 7;
      final fixture = await _fixture(seed, <String, List<int>>{
        'service/a': <int>[1, 2, 3],
      });
      final session = await V2StoreEngine(
        fixture.hostPlatform,
      ).openPlatformOnly();
      final storeKey = _storeKey(seed);
      try {
        final bytes = fixture.bytes;
        final frame = fixture.frames['service/a']!;
        final frameBytes = Uint8List.sublistView(
          bytes,
          frame.offset,
          frame.offset + frame.length,
        )..[24] ^= 1;
        final digest = digestFrame(frameBytes);
        final manifest = V2Manifest(<V2ManifestEntry>[
          V2ManifestEntry(
            key: 'service/a',
            frameLength: frame.length,
            frameDigest: digest,
          ),
        ]);
        final sealed = await _sealFixtureManifest(
          fixture: fixture,
          storeBytes: bytes,
          storeKey: storeKey,
          manifest: manifest,
          nonceMarker: 0x92,
        );
        try {
          expect(sealed.length, fixture.manifestLength);
          bytes.setRange(
            fixture.manifestOffset,
            fixture.manifestOffset + sealed.length,
            sealed,
          );
          fixture.files.replaceLiveBytes(bytes);
        } finally {
          _clear(sealed);
          manifest.clear();
          _clear(digest);
        }

        await expectLater(
          session.getBytes('service/a'),
          throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
        );
      } finally {
        _clear(storeKey);
        await session.close();
        await fixture.dispose();
      }
    });

    test(
      'does not read or authenticate an unrequested corrupted frame',
      () async {
        final fixture = await _fixture(8, <String, List<int>>{
          'service/a': <int>[1],
          'service/b': <int>[2],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final selected = fixture.frames['service/a']!;
          final ignored = fixture.frames['service/b']!;
          final bytes = fixture.bytes..[ignored.offset + 24] ^= 1;
          fixture.files.replaceLiveBytes(bytes);
          final readsBefore = fixture.files.reads.length;

          final value = await session.getBytes('service/a');
          try {
            expect(value, <int>[1]);
          } finally {
            if (value != null) _clear(value);
          }

          final reads = fixture.files.reads.skip(readsBefore).toList();
          expect(
            reads,
            contains(
              isA<MemoryPinnedRead>()
                  .having((read) => read.offset, 'offset', selected.offset)
                  .having((read) => read.length, 'length', selected.length),
            ),
          );
          expect(
            reads.where(
              (read) =>
                  read.offset == ignored.offset &&
                  read.length == ignored.length,
            ),
            isEmpty,
          );
        } finally {
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test('returns no partial map when a later selected frame fails', () async {
      final fixture = await _fixture(9, <String, List<int>>{
        'service/a': <int>[1],
        'service/b': <int>[2],
      });
      final probe = V2StoreEngineTestProbe();
      final session = await V2StoreEngine.debug(
        fixture.hostPlatform,
        probe,
      ).openPlatformOnly();
      try {
        final first = fixture.frames['service/a']!;
        final later = fixture.frames['service/b']!;
        final bytes = fixture.bytes..[later.offset + 24] ^= 1;
        fixture.files.replaceLiveBytes(bytes);
        final readsBefore = fixture.files.reads.length;

        await expectLater(
          session.getManyBytes(<String>['service/a', 'service/b']),
          throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
        );
        final frameReads = fixture.files.reads
            .skip(readsBefore)
            .where(
              (read) =>
                  read.offset == first.offset || read.offset == later.offset,
            )
            .toList();
        expect(frameReads.map((read) => read.offset), <int>[
          first.offset,
          later.offset,
        ]);
        expect(probe.discardedValueCount, 1);
        expect(probe.discardedValuesWereCleared, isTrue);

        fixture.files.replaceLiveBytes(fixture.bytes);
        final recovered = await session.getBytes('service/a');
        try {
          expect(recovered, <int>[1]);
        } finally {
          if (recovered != null) _clear(recovered);
        }
      } finally {
        await session.close();
        await fixture.dispose();
      }
    });
  });

  group('M4 cleanup failures', () {
    test(
      'withholds and clears a value when the read pin cannot close',
      () async {
        final fixture = await _fixture(14, <String, List<int>>{
          'service/a': <int>[1],
        });
        final probe = V2StoreEngineTestProbe();
        final session = await V2StoreEngine.debug(
          fixture.hostPlatform,
          probe,
        ).openPlatformOnly();
        try {
          fixture.files.closeFailure = const StoreFilesFailure(
            StoreFilesFailureCode.operationFailed,
          );

          await expectLater(
            session.getManyBytes(<String>['service/a']),
            throwsA(_failure(KeybayErrorCode.storageOperationFailed)),
          );
          expect(probe.discardedValueCount, 1);
          expect(probe.discardedValuesWereCleared, isTrue);
          expect(fixture.files.activeHandleCount, 0);
        } finally {
          fixture.files.closeFailure = null;
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test(
      'returns no session and clears its key when both open cleanups fail',
      () async {
        final fixture = await _fixture(15, <String, List<int>>{
          'service/a': <int>[1],
        });
        final protector = _CloseFailingProtector(fixture.host.protector);
        final host = ResolvedHost(
          binding: fixture.host.binding,
          files: fixture.files,
          protector: protector,
        );
        final probe = V2StoreEngineTestProbe();
        fixture.files.closeFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );
        try {
          await expectLater(
            V2StoreEngine.debug(
              FakeHostPlatform(host),
              probe,
            ).openPlatformOnly(),
            throwsA(_failure(KeybayErrorCode.platformOperationFailed)),
          );
          expect(protector.closeAttempts, 1);
          expect(fixture.files.closedHandleCount, 1);
          expect(probe.failedOpenKeyMaterialWasCleared, isTrue);
        } finally {
          fixture.files.closeFailure = null;
          await fixture.dispose();
        }
      },
    );

    test(
      'a primary authentication failure wins while both cleanups run',
      () async {
        final fixture = await _fixture(16, <String, List<int>>{
          'service/a': <int>[1],
        });
        final bytes = fixture.bytes
          ..[fixture.packageOffset + fixture.packageLength ~/ 2] ^= 1;
        fixture.files.replaceLiveBytes(bytes);
        final protector = _CloseFailingProtector(fixture.host.protector);
        final host = ResolvedHost(
          binding: fixture.host.binding,
          files: fixture.files,
          protector: protector,
        );
        fixture.files.closeFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );
        try {
          await expectLater(
            V2StoreEngine(FakeHostPlatform(host)).openPlatformOnly(),
            throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
          );
          expect(protector.closeAttempts, 1);
          expect(fixture.files.closedHandleCount, 1);
        } finally {
          fixture.files.closeFailure = null;
          await fixture.dispose();
        }
      },
    );
  });

  group('M4 state and generation races', () {
    test('maps file-adapter failures at open to the public taxonomy', () async {
      final fixture = await _fixture(10, <String, List<int>>{
        'service/a': <int>[1],
      });
      try {
        fixture.files.beforeOpen = () {
          throw const StoreFilesFailure(StoreFilesFailureCode.operationFailed);
        };
        await expectLater(
          V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
          throwsA(_failure(KeybayErrorCode.storageOperationFailed)),
        );
        expect(fixture.files.activeHandleCount, 0);
      } finally {
        fixture.files.beforeOpen = null;
        await fixture.dispose();
      }
    });

    test('maps an occupied transaction lock to storeBusy', () async {
      final fixture = await _fixture(21, <String, List<int>>{
        'service/a': <int>[1],
      });
      try {
        await fixture.files.withExclusiveTransaction((_) async {
          await expectLater(
            V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
            throwsA(_failure(KeybayErrorCode.storeBusy)),
          );
        });
      } finally {
        await fixture.dispose();
      }
    });

    test('closes the open pin when transaction cleanup fails', () async {
      final fixture = await _fixture(22, <String, List<int>>{
        'service/a': <int>[1],
      });
      try {
        fixture.files.transactionCleanupFailure = const StoreFilesFailure(
          StoreFilesFailureCode.operationFailed,
        );
        await expectLater(
          V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
          throwsA(_failure(KeybayErrorCode.storageOperationFailed)),
        );
        expect(fixture.files.closedHandleCount, 1);
        expect(fixture.files.activeHandleCount, 0);
      } finally {
        fixture.files.transactionCleanupFailure = null;
        await fixture.dispose();
      }
    });

    test(
      'open authenticates live before discarding abandoned staging',
      () async {
        final fixture = await _fixture(23, <String, List<int>>{
          'service/a': <int>[1],
        });
        try {
          fixture.files.hasTransactionArtifacts = true;
          final session = await V2StoreEngine(
            fixture.hostPlatform,
          ).openPlatformOnly();
          try {
            expect(fixture.files.hasTransactionArtifacts, isFalse);
            expect(fixture.files.openCallCount, 1);
            expect(await session.contains('service/a'), isTrue);
          } finally {
            await session.close();
          }
        } finally {
          fixture.files.hasTransactionArtifacts = false;
          await fixture.dispose();
        }
      },
    );

    test('authentication failure never discards abandoned staging', () async {
      final fixture = await _fixture(24, <String, List<int>>{
        'service/a': <int>[1],
      });
      try {
        final bytes = fixture.bytes
          ..[fixture.packageOffset + fixture.packageLength ~/ 2] ^= 1;
        fixture.files.replaceLiveBytes(bytes);
        fixture.files.hasTransactionArtifacts = true;

        await expectLater(
          V2StoreEngine(fixture.hostPlatform).openPlatformOnly(),
          throwsA(_failure(KeybayErrorCode.storeAuthenticationFailed)),
        );
        expect(fixture.files.hasLiveFile, isTrue);
        expect(fixture.files.hasTransactionArtifacts, isTrue);
        expect(fixture.files.activeHandleCount, 0);
      } finally {
        fixture.files.hasTransactionArtifacts = false;
        await fixture.dispose();
      }
    });

    test(
      'reads live during staging and fails if live disappears before pin',
      () async {
        final fixture = await _fixture(12, <String, List<int>>{
          'service/a': <int>[1],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final opensBeforeTransaction = fixture.files.openCallCount;
          fixture.files.hasTransactionArtifacts = true;
          expect(await session.contains('service/a'), isTrue);
          expect(fixture.files.openCallCount, opensBeforeTransaction + 1);

          fixture.files.hasTransactionArtifacts = false;
          fixture.files.beforeOpen = fixture.files.removeLiveBytes;
          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.storeStateConflict)),
          );
          expect(fixture.files.activeHandleCount, 0);
        } finally {
          fixture.files.beforeOpen = null;
          await session.close();
          await fixture.dispose();
        }
      },
    );

    test(
      'never mixes a replacement into an already-pinned generation',
      () async {
        final fixture = await _fixture(13, <String, List<int>>{
          'service/a': <int>[1, 2, 3],
        });
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          var replaced = false;
          fixture.files.beforeRead = (file, read) {
            if (replaced) return;
            replaced = true;
            fixture.files.replaceLiveBytes(Uint8List(20));
          };
          final readsBefore = fixture.files.reads.length;
          final value = await session.getBytes('service/a');
          try {
            expect(value, <int>[1, 2, 3]);
          } finally {
            if (value != null) _clear(value);
          }

          final reads = fixture.files.reads.skip(readsBefore).toList();
          expect(replaced, isTrue);
          expect(reads, isNotEmpty);
          expect(reads.map((read) => read.generation).toSet(), hasLength(1));
          expect(reads.first.generation, isNot(fixture.files.liveGeneration));

          await expectLater(
            session.contains('service/a'),
            throwsA(_failure(KeybayErrorCode.limitExceeded)),
          );
        } finally {
          fixture.files.beforeRead = null;
          await session.close();
          await fixture.dispose();
        }
      },
    );
  });
}

Future<V2StoreFixture> _fixture(
  int seed,
  Map<String, List<int>> records,
) async {
  final storeId = _storeId(seed);
  final storeKey = _storeKey(seed);
  try {
    return await buildV2StoreFixture(
      records: records,
      storeId: storeId,
      storeKey: storeKey,
      applicationId: 'dev.keybay.m4-adversarial-$seed',
      canonicalFileRoot: Uri.parse('file:///keybay-test/m4-adversarial-$seed/'),
    );
  } finally {
    _clear(storeId);
    _clear(storeKey);
  }
}

Future<Uint8List> _sealFixtureManifest({
  required V2StoreFixture fixture,
  required Uint8List storeBytes,
  required Uint8List storeKey,
  required V2Manifest manifest,
  required int nonceMarker,
}) async {
  final bootstrapBytes = Uint8List.fromList(
    Uint8List.sublistView(storeBytes, 0, fixture.bootstrapLength),
  );
  final sealedPackage = Uint8List.fromList(
    Uint8List.sublistView(
      storeBytes,
      fixture.packageOffset,
      fixture.packageOffset + fixture.packageLength,
    ),
  );
  final storeId = fixture.storeId;
  final domain = fixture.host.binding.domain.copyBytes();
  final nonce = Uint8List(V2StoreLimits.nonceBytes)..[0] = nonceMarker;
  try {
    return await sealManifest(
      storeKey: storeKey,
      storeId: storeId,
      storageDomain: domain,
      bootstrap: decodeBootstrap(bootstrapBytes),
      sealedPackage: sealedPackage,
      manifest: manifest,
      nonce: nonce,
    );
  } finally {
    _clear(bootstrapBytes);
    _clear(sealedPackage);
    _clear(storeId);
    _clear(domain);
    _clear(nonce);
  }
}

Uint8List _removeRange(Uint8List source, int offset, int length) =>
    Uint8List.fromList(<int>[
      ...Uint8List.sublistView(source, 0, offset),
      ...Uint8List.sublistView(source, offset + length),
    ]);

Uint8List _insertRange(Uint8List source, int offset, List<int> inserted) =>
    Uint8List.fromList(<int>[
      ...Uint8List.sublistView(source, 0, offset),
      ...inserted,
      ...Uint8List.sublistView(source, offset),
    ]);

Uint8List _storeId(int seed) => Uint8List.fromList(
  List<int>.generate(
    V2StoreLimits.storeIdBytes,
    (index) => (seed * 17 + index) & 0xff,
  ),
);

Uint8List _storeKey(int seed) => Uint8List.fromList(
  List<int>.generate(
    V2StoreLimits.storeKeyBytes,
    (index) => (seed * 29 + index) & 0xff,
  ),
);

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((error) => error.code, 'code', code);

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

final class _CloseFailingProtector implements PlatformProtector {
  _CloseFailingProtector(this._delegate);

  final PlatformProtector _delegate;
  int closeAttempts = 0;

  @override
  ResolvedApplicationBinding get binding => _delegate.binding;

  @override
  Future<PlatformRootLease?> openExisting(
    ProviderState state, {
    required PlatformInteraction interaction,
  }) async {
    final lease = await _delegate.openExisting(state, interaction: interaction);
    return lease == null ? null : _CloseFailingLease(lease, this);
  }

  @override
  Future<PlatformRootCreation> createOnly({
    required PlatformInteraction interaction,
  }) async {
    final creation = await _delegate.createOnly(interaction: interaction);
    return PlatformRootCreation(
      lease: _CloseFailingLease(creation.lease, this),
      disposition: creation.disposition,
    );
  }

  @override
  Future<PreparedPlatformReset> prepareReset({
    required PlatformInteraction interaction,
  }) => _delegate.prepareReset(interaction: interaction);
}

final class _CloseFailingLease implements PlatformRootLease {
  _CloseFailingLease(this._delegate, this._owner);

  final PlatformRootLease _delegate;
  final _CloseFailingProtector _owner;

  @override
  ProviderState get providerState => _delegate.providerState;

  @override
  Future<Uint8List> sealPackage({
    required Uint8List plaintext,
    required Uint8List aad,
  }) => _delegate.sealPackage(plaintext: plaintext, aad: aad);

  @override
  Future<Uint8List> openPackage({
    required Uint8List sealedPackage,
    required Uint8List aad,
  }) => _delegate.openPackage(sealedPackage: sealedPackage, aad: aad);

  @override
  Future<void> close() async {
    _owner.closeAttempts++;
    await _delegate.close();
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  }
}
