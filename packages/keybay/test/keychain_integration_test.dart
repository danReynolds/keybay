@Tags(['integration'])
@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:keybay/src/errors.dart';
import 'package:keybay/src/ffi/apple_host.dart';
import 'package:keybay/src/ffi/keychain.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:test/test.dart';

import 'support/macos_integration_home.dart';

/// Opt-in evidence for the exact Apple Keychain operations V2 uses.
///
/// Every test targets one fresh account under the frozen V2 service and
/// deletes only that exact item. Run with:
/// `KEYBAY_INTEGRATION=1 dart test test/keychain_integration_test.dart`.
void main() {
  final enabled = Platform.environment['KEYBAY_INTEGRATION'] == '1';
  final skip = enabled ? false : 'set KEYBAY_INTEGRATION=1';
  late AppleKeychainApi keychain;
  late String account;

  setUp(() {
    keychain = AppleKeychainApi.fileKeychainAt(
      '${macOSIntegrationAccountHome()}/Library/Keychains/login.keychain-db',
    );
    account =
        'v2-ffi-itest-$pid-${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
  });
  tearDown(() => keychain.delete(v2MacOSLoginKeychainService, account));

  test('bounded read and exact add/delete preserve the first root', () async {
    final first = Uint8List.fromList(List<int>.generate(72, (i) => i));
    final replacement = Uint8List.fromList(List<int>.filled(72, 0xa5));

    expect(
      await keychain.getBounded(
        v2MacOSLoginKeychainService,
        account,
        maxValueBytes: v2MacOSLoginKeychainMaxRootRecordBytes,
      ),
      isNull,
    );
    expect(
      await keychain.addIfAbsent(
        v2MacOSLoginKeychainService,
        account,
        first,
        label: v2MacOSLoginKeychainLabel,
      ),
      isTrue,
    );
    expect(
      await keychain.addIfAbsent(
        v2MacOSLoginKeychainService,
        account,
        replacement,
        label: v2MacOSLoginKeychainLabel,
      ),
      isFalse,
    );
    expect(await keychain.exists(v2MacOSLoginKeychainService, account), isTrue);
    expect(
      await keychain.getBounded(
        v2MacOSLoginKeychainService,
        account,
        maxValueBytes: v2MacOSLoginKeychainMaxRootRecordBytes,
      ),
      first,
    );

    await keychain.delete(v2MacOSLoginKeychainService, account);
    expect(
      await keychain.exists(v2MacOSLoginKeychainService, account),
      isFalse,
    );
    await keychain.delete(v2MacOSLoginKeychainService, account);
  }, skip: skip);

  test('bounded read rejects an oversized root before copying it', () async {
    expect(
      await keychain.addIfAbsent(
        v2MacOSLoginKeychainService,
        account,
        Uint8List(v2MacOSLoginKeychainMaxRootRecordBytes + 1),
        label: v2MacOSLoginKeychainLabel,
      ),
      isTrue,
    );
    await expectLater(
      keychain.getBounded(
        v2MacOSLoginKeychainService,
        account,
        maxValueBytes: v2MacOSLoginKeychainMaxRootRecordBytes,
      ),
      throwsA(isA<KeystoreOperationFailed>()),
    );
  }, skip: skip);

  test(
    'unsigned host inspection is read-only and finds no signed identity',
    () {
      expect(
        AppleHostApi.macOS().macOSSignedApplicationIdentifierOrNull(),
        isNull,
      );
    },
    skip: skip,
  );
}
