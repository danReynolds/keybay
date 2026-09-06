@Tags(['integration'])
@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:keybay/src/errors.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:test/test.dart';

import 'support/macos_integration_home.dart';

/// Opt-in smoke test for the exact login-Keychain primitive.
///
/// Each run uses a fresh provider address and deletes only the item it created.
/// Run explicitly with `KEYBAY_INTEGRATION=1 dart test -t integration`.
void main() {
  final enabled = Platform.environment['KEYBAY_INTEGRATION'] == '1';
  final skip = enabled ? false : 'set KEYBAY_INTEGRATION=1';
  final roots = AppleMacOSLoginKeychainRootStore(
    accountHome: macOSIntegrationAccountHome(),
  );
  late String address;

  setUp(() async {
    final random = Random.secure();
    address =
        'v2-itest-$pid-${DateTime.now().microsecondsSinceEpoch}-'
        '${random.nextInt(0x7fffffff)}';
    expect(await roots.exists(address), isFalse);
  });
  tearDown(() => roots.delete(address));

  test(
    'create, adopt, read, and delete stay on the exact login Keychain',
    () async {
      final first = Uint8List.fromList(
        List<int>.generate(72, (index) => index),
      );
      final replacement = Uint8List.fromList(List<int>.filled(72, 0xa5));

      expect(await roots.createIfAbsent(address, first), isTrue);
      expect(await roots.createIfAbsent(address, replacement), isFalse);
      expect(await roots.read(address), first);
      expect(await roots.exists(address), isTrue);
      await roots.delete(address);
      expect(await roots.exists(address), isFalse);
      expect(await roots.read(address), isNull);
    },
    skip: skip,
  );

  test(
    'V2 read rejects a provider value above its fixed allocation bound',
    () async {
      final oversized = Uint8List(v2MacOSLoginKeychainMaxRootRecordBytes + 1);
      expect(await roots.createIfAbsent(address, oversized), isTrue);
      await expectLater(
        roots.read(address),
        throwsA(isA<KeystoreOperationFailed>()),
      );
    },
    skip: skip,
  );
}
