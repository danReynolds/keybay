@Tags(['integration'])
@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:secret_store/src/errors.dart';
import 'package:secret_store/src/ffi/keychain.dart';
import 'package:test/test.dart';

/// Exercises the REAL macOS login Keychain. Opt-in — these create and delete
/// items under a throwaway service and may surface an auth dialog on some
/// machines. Run with:
///   SECRET_STORE_INTEGRATION=1 dart test -t integration
void main() {
  // Runtime gate (not a compile-time define): export SECRET_STORE_INTEGRATION=1.
  final envEnabled = Platform.environment['SECRET_STORE_INTEGRATION'] == '1';
  final skip = envEnabled ? false : 'set SECRET_STORE_INTEGRATION=1';

  final api = MacKeychainApi();
  const service = 'ca.danreynolds.secret_store.itest';

  Uint8List bytes(List<int> v) => Uint8List.fromList(v);

  Future<void> cleanup() async {
    for (final acct in ['a', 'b', 'k']) {
      await api.delete(service, acct);
    }
  }

  setUp(cleanup);
  tearDown(cleanup);

  test('add / get / update / delete round-trips real bytes', () async {
    expect(await api.get(service, 'k'), isNull);

    await api.set(service, 'k', bytes([1, 2, 3, 0, 255]), label: 'itest key');
    expect(await api.get(service, 'k'), [1, 2, 3, 0, 255]);

    // upsert (duplicate -> update)
    await api.set(service, 'k', bytes([9, 9]));
    expect(await api.get(service, 'k'), [9, 9]);

    await api.delete(service, 'k');
    expect(await api.get(service, 'k'), isNull);
    await api.delete(service, 'k'); // idempotent
  }, skip: skip);

  test('enumerates all accounts under a service', () async {
    await api.set(service, 'a', bytes([1]));
    await api.set(service, 'b', bytes([2, 2]));
    final all = await api.getAll(service);
    expect(all.keys.toSet(), containsAll(<String>{'a', 'b'}));
    expect(all['a'], [1]);
    expect(all['b'], [2, 2]);
  }, skip: skip);

  test('binary values with embedded NULs survive the CFData round-trip',
      () async {
    final v = bytes(List.generate(64, (i) => (i * 7) % 256));
    await api.set(service, 'k', v);
    expect(await api.get(service, 'k'), v);
  }, skip: skip);

  test('probe reports available/unlocked on a normal session', () async {
    final p = await api.probe(service);
    expect(p.available, isTrue);
  }, skip: skip);

  test('nonInteractive mode round-trips on an unlocked keychain', () async {
    // With the keychain unlocked, kSecUseAuthenticationUIFail must be inert;
    // its effect (fail-fast KeystoreLocked instead of a GUI prompt) only
    // kicks in when interaction would be required.
    final ni = MacKeychainApi(nonInteractive: true);
    await ni.set(service, 'k', bytes([4, 2]), label: 'itest ni');
    expect(await ni.get(service, 'k'), [4, 2]);
    await ni.delete(service, 'k');
    expect(await ni.get(service, 'k'), isNull);
  }, skip: skip);

  group('Data Protection keychain', () {
    // The SUCCESS path needs a signed, entitled app bundle, which CI can't
    // produce — that is verified manually (see doc/design.md). What IS testable
    // here, including on the unsigned CI runner, is (a) the binding constructs,
    // and (b) an unentitled process is refused with the −34018 → typed error,
    // never silently falling back to the login keychain.
    test('binding constructs', () {
      expect(MacKeychainApi.dataProtection(), isNotNull);
    }, skip: skip);

    test('an unentitled process is refused, not silently downgraded', () async {
      final dp = MacKeychainApi.dataProtection();
      // errSecMissingEntitlement (−34018) → KeystoreUnreachable with guidance.
      // (An entitled app would instead store successfully.)
      await expectLater(
        dp.set(service, 'dp', bytes([1, 2, 3])),
        throwsA(
          isA<KeystoreUnreachable>()
              .having((e) => e.toString(), 'toString', contains('entitlement')),
        ),
      );
      // And nothing was written to the login keychain as a fallback.
      expect(await api.get(service, 'dp'), isNull);
    }, skip: skip);
  });
}
