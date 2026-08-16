@Tags(['unit'])
library;

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
// The concrete backends are internal (not exported); their unit tests reach
// them directly.
import 'package:keybay/src/backends/encrypted_file_backend.dart';
import 'package:keybay/src/backends/keystore_backend.dart';
import 'package:keybay/src/ffi/keystore_api.dart';
import 'package:keybay/src/ffi/posix_file.dart';
import 'package:keybay/src/key_source.dart';
import 'package:test/test.dart';

/// In-memory [KeystoreApi] fake: models (service, account) -> bytes with upsert
/// and enumeration, so the backend/key-source logic is tested without the real
/// Keychain (the FFI itself is covered by keychain_integration_test).
class FakeKeystoreApi implements KeystoreApi {
  final Map<String, Map<String, Uint8List>> _store = {};
  bool locked = false;
  bool available = true;
  int setCalls = 0;

  @override
  Future<Uint8List?> get(String service, String account) async {
    _checkReachable();
    return _store[service]?[account];
  }

  @override
  Future<bool> exists(String service, String account) async {
    _checkReachable();
    return _store[service]?.containsKey(account) ?? false;
  }

  @override
  Future<void> set(String service, String account, Uint8List value,
      {String? label}) async {
    _checkReachable();
    setCalls++;
    (_store[service] ??= {})[account] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String service, String account) async {
    _checkReachable();
    _store[service]?.remove(account);
  }

  @override
  Future<void> clear(String service) async {
    _checkReachable();
    _store.remove(service);
  }

  @override
  Future<Map<String, Uint8List>> getAll(String service) async {
    _checkReachable();
    return Map.of(_store[service] ?? {});
  }

  @override
  Future<KeystoreProbe> probe(String service) async =>
      KeystoreProbe(available: available, locked: locked);

  void _checkReachable() {
    if (!available) throw const KeystoreUnreachable();
    if (locked) throw const KeystoreLocked();
  }
}

class FakeAddOnlyKeystoreApi extends FakeKeystoreApi
    implements AddOnlyKeystoreApi {
  int addIfAbsentCalls = 0;

  @override
  Future<bool> addIfAbsent(
    String service,
    String account,
    Uint8List value, {
    String? label,
  }) async {
    _checkReachable();
    addIfAbsentCalls++;
    final items = _store[service] ??= {};
    if (items.containsKey(account)) return false;
    items[account] = Uint8List.fromList(value);
    return true;
  }
}

class _TwoRootRaceApi extends FakeAddOnlyKeystoreApi {
  var _getCalls = 0;
  final _firstPair = Completer<void>();
  final _secondPair = Completer<void>();

  @override
  Future<Uint8List?> get(String service, String account) async {
    _checkReachable();
    final captured = _store[service]?[account];
    final call = ++_getCalls;
    final gate = call <= 2 ? _firstPair : _secondPair;
    if (call == 2 || call == 4) gate.complete();
    await gate.future;
    return captured == null ? null : Uint8List.fromList(captured);
  }
}

class _DuplicateThenMissingApi extends FakeKeystoreApi
    implements AddOnlyKeystoreApi {
  @override
  Future<bool> addIfAbsent(
    String service,
    String account,
    Uint8List value, {
    String? label,
  }) async =>
      false;
}

class _WriteFailsFs extends SecureFileSystem {
  const _WriteFailsFs();

  @override
  void writeAtomicSync(String path, Uint8List bytes) {
    throw SecureFileError('write', path, 28);
  }
}

void main() {
  Uint8List b(List<int> v) => Uint8List.fromList(v);

  group('KeystoreBackend', () {
    late FakeKeystoreApi api;
    late KeystoreBackend be;
    setUp(() {
      api = FakeKeystoreApi();
      be = KeystoreBackend(service: 'svc', api: api);
    });

    test('read/write/contains/delete/enumerate', () async {
      expect(await be.read('k'), isNull);
      await be.write('k', b([1, 2]), label: 'lbl');
      expect(await be.read('k'), [1, 2]);
      expect(await be.contains('k'), isTrue);

      await be.write('j', b([3]));
      expect((await be.readAll()).keys.toSet(), {'k', 'j'});

      await be.delete('k');
      expect(await be.contains('k'), isFalse);

      await be.deleteAll();
      expect(await be.readAll(), isEmpty);
    });

    test('capabilities: enumerates and is persistent', () {
      expect(be.capabilities.enumeration, isTrue);
      expect(be.capabilities.persistent, isTrue);
    });

    test('describe reflects locked/available', () async {
      api.locked = true;
      final info = await be.describe();
      expect(info.scheme, StorageScheme.nativeItems);
      // Native Apple Keychain items do not expose a per-item hardware
      // attestation through this API. Keep the level absent rather than
      // inferring one from the device's unrelated Secure Enclave capability.
      expect(info.level, isNull);
      expect(info.locked, isTrue);
    });
  });

  group('SystemKeySource + EncryptedFileBackend (model B)', () {
    test('wraps the container key in the keychain; container stays encrypted',
        () async {
      final api = FakeKeystoreApi();
      final ks = SystemKeySource(service: 'dune/uuid', api: api);
      // Uses a real temp file for the container.
      final dir = Directory.systemTemp.createTempSync('ss_modelb_');
      Process.runSync('chmod',
          ['700', dir.path]); // private store dir (umask is 0755 on Linux)
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/secrets.enc';

      final be = EncryptedFileBackend(
          path: path, keySource: ks, contextSalt: b([1, 2, 3, 4]));
      // A distinctive ASCII plaintext marker, so "the container is ciphertext"
      // is a real assertion: the previous value [9,9,9] stringifies to tab
      // bytes and could never contain the digits "999" it checked for — the
      // test passed even against a hypothetical plaintext container.
      const marker = 'PLAINTEXT-MARKER-9f3a2b';
      final value = Uint8List.fromList(marker.codeUnits);
      await be.write('db_key', value, label: 'DB key');
      expect(await be.read('db_key'), value);

      // The key lives in the (fake) keychain, exactly one item, 32 bytes.
      final stored = await api.getAll('dune/uuid');
      expect(stored.keys, ['store-key']);
      expect(stored['store-key'], hasLength(storeKeyLength));

      // The on-disk container is ciphertext — the marker must not survive in
      // the clear.
      final raw = File(path).readAsBytesSync();
      expect(String.fromCharCodes(raw), isNot(contains(marker)),
          reason: 'container must be ciphertext, not plaintext');
    });

    test('locked keychain surfaces as StoreKeyMissing-free typed error',
        () async {
      final api = FakeKeystoreApi()..locked = true;
      final ks = SystemKeySource(service: 's', api: api);
      final dir = Directory.systemTemp.createTempSync('ss_locked_');
      Process.runSync('chmod',
          ['700', dir.path]); // private store dir (umask is 0755 on Linux)
      addTearDown(() => dir.deleteSync(recursive: true));
      final be = EncryptedFileBackend(path: '${dir.path}/c.enc', keySource: ks);
      // Reading the key throws KeystoreLocked from the fake.
      await expectLater(be.write('k', b([1])), throwsA(isA<KeystoreLocked>()));
    });

    test('one identity lock coordinates first writes across container roots',
        () async {
      final api = FakeKeystoreApi();
      final dir = Directory.systemTemp.createTempSync('ss_split_root_');
      Process.runSync('chmod', <String>['700', dir.path]);
      final rootA = Directory('${dir.path}/a')..createSync();
      final rootB = Directory('${dir.path}/b')..createSync();
      Process.runSync('chmod', <String>['700', rootA.path]);
      Process.runSync('chmod', <String>['700', rootB.path]);
      addTearDown(() => dir.deleteSync(recursive: true));
      final identityLock = '${dir.path}/identity/app.store-key.lock';
      EncryptedFileBackend backend(String root) => EncryptedFileBackend(
            path: '$root/secrets.enc',
            keySource: SystemKeySource(
              service: 'same-app',
              api: api,
              coordinationLockPath: identityLock,
            ),
          );
      final first = backend(rootA.path);
      final second = backend(rootB.path);

      await Future.wait(<Future<void>>[
        first.write('a', b(<int>[1])),
        second.write('b', b(<int>[2])),
      ]);

      expect(api.setCalls, 1,
          reason: 'only the identity-lock winner may create the shared key');
      expect(await first.read('a'), <int>[1]);
      expect(await second.read('b'), <int>[2]);
    });

    test('atomic provider creation makes racing writers adopt one key',
        () async {
      final api = FakeAddOnlyKeystoreApi();
      final first = SystemKeySource(service: 'same-app', api: api);
      final second = SystemKeySource(service: 'same-app', api: api);

      final created = await Future.wait([first.create(), second.create()]);

      expect(api.addIfAbsentCalls, 2);
      expect(api.setCalls, 0,
          reason: 'atomic first creation must never fall back to upsert');
      expect(created[0], created[1],
          reason: 'the duplicate writer must adopt the winning key');
      expect(await first.read(), created[0]);
      expect(first.canRollbackCreatedKey, isFalse,
          reason: 'a published key may already protect another container');
    });

    test('atomic provider protects simultaneous first writes in split roots',
        () async {
      final api = _TwoRootRaceApi();
      final dir = Directory.systemTemp.createTempSync('ss_atomic_split_root_');
      Process.runSync('chmod', <String>['700', dir.path]);
      final rootA = Directory('${dir.path}/a')..createSync();
      final rootB = Directory('${dir.path}/b')..createSync();
      Process.runSync('chmod', <String>['700', rootA.path]);
      Process.runSync('chmod', <String>['700', rootB.path]);
      addTearDown(() => dir.deleteSync(recursive: true));
      EncryptedFileBackend backend(String root) => EncryptedFileBackend(
            path: '$root/secrets.enc',
            keySource: SystemKeySource(service: 'same-app', api: api),
          );
      final first = backend(rootA.path);
      final second = backend(rootB.path);

      await Future.wait([
        first.write('a', b([1])),
        second.write('b', b([2])),
      ]);

      expect(api.addIfAbsentCalls, 2,
          reason: 'the fixture must make both first writers attempt creation');
      expect(await first.read('a'), [1]);
      expect(await second.read('b'), [2]);
    });

    test('failed Apple-style first write retains its published key and heals',
        () async {
      final api = FakeAddOnlyKeystoreApi();
      final dir = Directory.systemTemp.createTempSync('ss_atomic_retry_');
      Process.runSync('chmod', <String>['700', dir.path]);
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/secrets.enc';
      final source = SystemKeySource(service: 'same-app', api: api);
      final failing = EncryptedFileBackend(
        path: path,
        keySource: source,
        fs: const _WriteFailsFs(),
      );

      await expectLater(
          failing.write('k', b([1])), throwsA(isA<SecureFileError>()));
      expect(await source.read(), hasLength(storeKeyLength),
          reason: 'an atomically published key may already have another user');
      expect(File(path).existsSync(), isFalse);

      final retry = EncryptedFileBackend(path: path, keySource: source);
      await retry.write('k', b([2]));
      expect(await retry.read('k'), [2]);
    });

    test('duplicate followed by deletion fails instead of overwriting',
        () async {
      final source = SystemKeySource(
        service: 'same-app',
        api: _DuplicateThenMissingApi(),
      );
      await expectLater(
        source.create(),
        throwsA(
          isA<KeystoreOperationFailed>().having(
            (error) => error.message,
            'message',
            contains('disappeared'),
          ),
        ),
      );
    });

    test('SystemKeySource.describe checks presence without reading the key',
        () async {
      final src =
          SystemKeySource(service: 'svc', api: _GetMustNotBeCalledApi());
      final status = await src.describe();
      expect(status.present, isTrue);
      expect(status.available, isTrue);
    });

    test(
        'SystemKeySource.describe never throws: a failing presence check is '
        'reported in detail', () async {
      // The probe says healthy but the keystore locks between it and the
      // attributes-only presence check. Diagnostics must degrade, not raise.
      final src = SystemKeySource(service: 'svc', api: _ExistsFailsApi());
      final status = await src.describe(); // must not throw
      expect(status.present, isFalse);
      expect(status.available, isTrue);
      expect(status.locked, isTrue);
      expect(status.detail, contains('locked during presence check'));
    });

    test('SystemKeySource.describe downgrades a failed presence check',
        () async {
      final src = SystemKeySource(
        service: 'svc',
        api: _ExistsUnavailableApi(),
      );
      final status = await src.describe();
      expect(status.present, isFalse);
      expect(status.available, isFalse);
      expect(status.locked, isFalse);
      expect(status.detail, contains('presence backend unavailable'));
    });
  });
}

/// A key exists, but fetching its value would be an error for diagnostics.
class _GetMustNotBeCalledApi extends FakeKeystoreApi {
  @override
  Future<bool> exists(String service, String account) async => true;

  @override
  Future<Uint8List?> get(String service, String account) async {
    throw StateError('describe() must not read the key value');
  }
}

/// Probe reports healthy, but the attributes-only presence check fails.
class _ExistsFailsApi extends FakeKeystoreApi {
  @override
  Future<bool> exists(String service, String account) async {
    throw const KeystoreLocked('locked during presence check');
  }
}

class _ExistsUnavailableApi extends FakeKeystoreApi {
  @override
  Future<bool> exists(String service, String account) async {
    throw const KeystoreUnreachable('presence backend unavailable');
  }
}

// dart:io used via Directory/File above.
