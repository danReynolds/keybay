@Tags(['unit'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:test/test.dart';

import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_fakes.dart';
import 'support/v2_store_fixture.dart';

// Every case changes one valid, small store. The ordinary suite runs 25 cases
// per mutation; the scheduled lane varies the seed and increases the depth.
// Only synthetic data is used, and failures report no key or store bytes.
void main() {
  final iterations = _setting('KEYBAY_FUZZ_ITERATIONS', 200, 1, 200000);
  final seed = _setting('KEYBAY_FUZZ_SEED', 0x4b425632, 0, 0xffffffff);

  test(
    'V2 authenticated reader canary: seed=$seed cases=$iterations',
    () async {
      final random = Random(seed);
      final records = <String, List<int>>{
        'canary/a': <int>[1, 2, 3],
        'canary/z': List<int>.generate(257, (_) => random.nextInt(256)),
      };
      final fixture = await buildV2StoreFixture(records: records);
      final original = fixture.bytes;
      try {
        // Establish the positive oracle before trying modified generations.
        final session = await V2StoreEngine(
          fixture.hostPlatform,
        ).openPlatformOnly();
        try {
          final values = await session.getManyBytes(records.keys);
          try {
            for (final entry in records.entries) {
              _check(
                _sameBytes(values[entry.key], entry.value),
                'The unmodified control did not return its original values.',
              );
            }
          } finally {
            _clearValues(values);
          }
        } finally {
          await session.close();
        }

        for (var index = 0; index < iterations; index++) {
          final mutation = _Mutation.values[index % _Mutation.values.length];
          try {
            await _runCase(fixture, original, mutation, random, index);
          } on Object catch (error, stack) {
            final detail = error is TestFailure
                ? error.message
                : 'Unexpected ${error.runtimeType}';
            Error.throwWithStackTrace(
              TestFailure(
                'V2 canary seed=$seed case=$index mutation=${mutation.name}: '
                '$detail. Reproduce with KEYBAY_FUZZ_SEED=$seed '
                'KEYBAY_FUZZ_ITERATIONS=${index + 1}.',
              ),
              stack,
            );
          }
        }
      } finally {
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

enum _Mutation {
  providerLength,
  packageLength,
  manifestLength,
  truncation,
  packageAuthentication,
  manifestAuthentication,
  frameDigest,
  frameAuthentication,
}

Future<void> _runCase(
  V2StoreFixture fixture,
  Uint8List original,
  _Mutation mutation,
  Random random,
  int index,
) async {
  // Fresh adapters keep fake read histories bounded at weekly depth; the
  // fixture's disposable provider root is shared, with no native provider I/O.
  final files = MemoryPinnedStoreFiles(
    fixture.host.binding,
    liveBytes: original,
  );
  final host = ResolvedHost(
    binding: fixture.host.binding,
    files: files,
    protector: fixture.host.protector,
  );
  final probe = V2StoreEngineTestProbe();
  final session = await V2StoreEngine.debug(
    FakeHostPlatform(host),
    probe,
  ).openPlatformOnly();
  var bytes = Uint8List.fromList(original);
  var expected = KeybayErrorCode.storeAuthenticationFailed;
  try {
    final view = ByteData.sublistView(bytes);
    switch (mutation) {
      case _Mutation.providerLength:
        view.setUint32(6, _oversized(random, V2StoreLimits.providerStateBytes));
        expected = KeybayErrorCode.limitExceeded;
      case _Mutation.packageLength:
        view.setUint32(
          fixture.bootstrapLength - v2BootstrapLengthBytes,
          _oversized(random, V2StoreLimits.sealedPackageBytes),
        );
        expected = KeybayErrorCode.limitExceeded;
      case _Mutation.manifestLength:
        view.setUint32(
          fixture.trailerOffset,
          _oversized(random, V2StoreLimits.sealedManifestBytes),
        );
        expected = KeybayErrorCode.limitExceeded;
      case _Mutation.truncation:
        bytes = Uint8List.fromList(
          bytes.sublist(0, random.nextInt(bytes.length)),
        );
      case _Mutation.packageAuthentication:
        _flip(bytes, fixture.packageOffset, fixture.packageLength, random);
      case _Mutation.manifestAuthentication:
        _flip(bytes, fixture.manifestOffset, fixture.manifestLength, random);
      case _Mutation.frameDigest:
      case _Mutation.frameAuthentication:
        // Corrupt the later selected frame: a failure must also discard and
        // clear the already-decrypted first value, without returning a map.
        final frame = fixture.frames['canary/z']!;
        _flip(bytes, frame.offset, frame.length, random);
        if (mutation == _Mutation.frameAuthentication) {
          await _authenticateChangedDigest(fixture, bytes, index);
        }
    }
    _check(bytes.length <= original.length, 'The input exceeded its bound.');
    files.replaceLiveBytes(bytes);
    final readsBefore = files.reads.length;
    Map<String, Uint8List?>? output;
    KeybayException? failure;
    try {
      output = await session.getManyBytes(fixture.frames.keys);
    } on KeybayException catch (error) {
      failure = error;
    } finally {
      if (output != null) _clearValues(output);
    }
    _check(failure != null, 'A modified store returned plaintext.');
    // Arbitrary truncation may hit the whole-file minimum or a component
    // bound before authentication; it may never become a provider/I/O error.
    _check(
      failure!.code == expected ||
          (mutation == _Mutation.truncation &&
              failure.code == KeybayErrorCode.limitExceeded),
      'Unexpected typed failure ${failure.code.name}; expected ${expected.name}.',
    );
    final reads = files.reads.skip(readsBefore).toList();
    _check(
      reads.every(
        (read) =>
            read.offset >= 0 &&
            read.length <= original.length &&
            read.offset + read.length <= bytes.length,
      ),
      'A component read exceeded the bounded input.',
    );
    if (mutation == _Mutation.providerLength) {
      _check(
        reads.length == 1 && reads.single.length == v2BootstrapCoreFixedBytes,
        'An oversized provider length caused a variable-length read.',
      );
    } else if (mutation == _Mutation.packageLength) {
      _check(
        reads.every((read) => read.length <= fixture.bootstrapLength),
        'An oversized package length caused a package read.',
      );
    } else if (mutation == _Mutation.manifestLength) {
      _check(
        reads.every((read) => read.length <= fixture.packageLength),
        'An oversized manifest length caused a manifest read.',
      );
    } else if (mutation == _Mutation.frameDigest ||
        mutation == _Mutation.frameAuthentication) {
      _check(
        probe.discardedValueCount == 1 && probe.discardedValuesWereCleared,
        'A failed later frame did not clear the earlier selected value.',
      );
    }
    _check(files.activeHandleCount == 0, 'A failed read left a live pin.');
  } finally {
    await session.close();
    files.removeLiveBytes();
  }
}

// Updating both the digest and the authenticated manifest deliberately gets
// past the digest oracle. Frame AEAD must independently reject the corruption.
Future<void> _authenticateChangedDigest(
  V2StoreFixture fixture,
  Uint8List bytes,
  int index,
) async {
  final entries = <V2ManifestEntry>[];
  for (final entry in fixture.frames.entries) {
    final frame = entry.value;
    final digest = digestFrame(
      Uint8List.sublistView(bytes, frame.offset, frame.offset + frame.length),
    );
    entries.add(
      V2ManifestEntry(
        key: entry.key,
        frameLength: frame.length,
        frameDigest: digest,
      ),
    );
  }
  final manifest = V2Manifest(entries);
  final key = fixture.copyStoreKey();
  final id = fixture.storeId;
  final domain = fixture.host.binding.domain.copyBytes();
  // This domain byte differs from every fixture nonce; the case index makes
  // each changed manifest nonce unique under this disposable store key.
  final nonce = Uint8List(V2StoreLimits.nonceBytes)..[0] = 0x46;
  ByteData.sublistView(nonce).setUint64(16, index);
  try {
    final sealed = await sealManifest(
      storeKey: key,
      storeId: id,
      storageDomain: domain,
      bootstrap: decodeBootstrap(
        Uint8List.sublistView(bytes, 0, fixture.bootstrapLength),
      ),
      sealedPackage: Uint8List.sublistView(
        bytes,
        fixture.packageOffset,
        fixture.packageOffset + fixture.packageLength,
      ),
      manifest: manifest,
      nonce: nonce,
    );
    _check(
      sealed.length == fixture.manifestLength,
      'Resealing changed layout.',
    );
    bytes.setRange(fixture.manifestOffset, fixture.trailerOffset, sealed);
  } finally {
    manifest.clear();
    _clear(key);
  }
}

int _oversized(Random random, int limit) => switch (random.nextInt(3)) {
  0 => limit + 1,
  1 => 0xffffffff,
  _ => limit + 1 + random.nextInt(0xffffffff - limit),
};

void _flip(Uint8List bytes, int offset, int length, Random random) {
  bytes[offset + random.nextInt(length)] ^= 1 << random.nextInt(8);
}

int _setting(String name, int fallback, int minimum, int maximum) {
  final text = Platform.environment[name];
  if (text == null) return fallback;
  final value = int.tryParse(text);
  if (value == null || value < minimum || value > maximum) {
    throw ArgumentError('$name must be an integer in $minimum..$maximum.');
  }
  return value;
}

void _check(bool condition, String message) {
  if (!condition) throw TestFailure(message);
}

bool _sameBytes(Uint8List? actual, List<int> expected) =>
    actual != null &&
    actual.length == expected.length &&
    List<bool>.generate(
      expected.length,
      (index) => actual[index] == expected[index],
    ).every((equal) => equal);

void _clearValues(Map<String, Uint8List?> values) {
  for (final value in values.values) {
    if (value != null) _clear(value);
  }
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
