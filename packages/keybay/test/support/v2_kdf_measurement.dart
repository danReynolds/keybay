// Compile with `dart compile exe` before running. Measures fresh processes so
// peak RSS is not inherited from earlier derivations or a Flutter test runner.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && arguments.single == '--baseline') {
    stdout.writeln(jsonEncode({'peakRssBytes': ProcessInfo.maxRss}));
    return;
  }
  if (arguments.length == 1 && arguments.single == '--derive') {
    // Public vector inputs only. Verify the measured production path as well
    // as timing it; never print the derived key.
    final phrase = Uint8List.fromList('correct horse battery staple'.codeUnits);
    final salt = Uint8List.fromList(List<int>.generate(16, (index) => index));
    final stopwatch = Stopwatch()..start();
    final key = await const Argon2idV2PassphraseDeriver().derive(
      passphrase: phrase,
      profileId: v2FirstPassphraseProfile,
      salt: salt,
    );
    stopwatch.stop();
    try {
      const expected =
          '853b272a44db1421c02962669a55eb0994f3cab385ed1c4c79253eee19bab49e';
      if (key.length != 32 ||
          List.generate(
            32,
            (index) => int.parse(
              expected.substring(index * 2, index * 2 + 2),
              radix: 16,
            ),
          ).asMap().entries.any((entry) => key[entry.key] != entry.value)) {
        throw StateError('Production KDF did not match the reference vector.');
      }
      stdout.writeln(
        jsonEncode({
          'derivationMicroseconds': stopwatch.elapsedMicroseconds,
          'peakRssBytes': ProcessInfo.maxRss,
          'referenceVectorMatched': true,
        }),
      );
    } finally {
      key.fillRange(0, key.length, 0);
      phrase.fillRange(0, phrase.length, 0);
    }
    return;
  }
  if (arguments.isNotEmpty) {
    throw ArgumentError('Run the compiled executable without arguments.');
  }

  Future<Map<String, Object?>> sample(String mode) async {
    final process = await Process.run(Platform.resolvedExecutable, [mode]);
    if (process.exitCode != 0) {
      throw StateError('KDF measurement child failed (${process.exitCode}).');
    }
    return jsonDecode(process.stdout as String) as Map<String, Object?>;
  }

  final baseline = await sample('--baseline');
  final measurements = <Map<String, Object?>>[];
  for (var index = 0; index < 5; index++) {
    measurements.add(await sample('--derive'));
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version,
      'profile': {
        'id': v2FirstPassphraseProfile,
        'memoryKiB': v2PassphraseProfile1MemoryKiB,
        'iterations': v2PassphraseProfile1Iterations,
        'parallelism': v2PassphraseProfile1Parallelism,
      },
      'baseline': baseline,
      'freshProcessSamples': measurements,
      'limitations': [
        'Peak RSS includes the Dart runtime and allocator.',
        'These observations have no automatic performance acceptance threshold.',
        'They apply only to the measured host and compiled SDK.',
      ],
    }),
  );
}
