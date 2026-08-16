@Tags(['unit'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/backend.dart';
import 'package:keybay/src/backends/scheme_tracking_backend.dart';
import 'package:keybay/src/errors.dart';
import 'package:keybay/src/ffi/posix_file.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String marker;

  setUp(() {
    root = Directory.systemTemp.createTempSync('keybay-scheme-test-');
    marker = '${root.path}/store/.scheme';
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  MacOSSchemeGuard guard(String group) => MacOSSchemeGuard(
        appId: 'com.example.app',
        markerPath: marker,
        accessGroup: group,
      );

  test('records one private native scheme marker and accepts the same group',
      () async {
    await guard('TEAM.com.example.app').recordNativeSelection();
    expect(File(marker).existsSync(), isTrue);
    expect(File(marker).statSync().mode & 0x3F, 0);
    expect(() => guard('TEAM.com.example.app').verifyNativeSelection(),
        returnsNormally);
  });

  test('recorded native use blocks encrypted-file fallback', () async {
    await guard('TEAM.com.example.app').recordNativeSelection();
    expect(
      () => MacOSSchemeGuard(
        appId: 'com.example.app',
        markerPath: marker,
      ).verifyFileSelection(),
      throwsA(
        isA<MigrationRequired>()
            .having((e) => e.from, 'from', StorageScheme.nativeItems)
            .having((e) => e.to, 'to', StorageScheme.encryptedFile),
      ),
    );
  });

  test('changed access group fails closed', () async {
    await guard('TEAM.one').recordNativeSelection();
    expect(
      () => guard('TEAM.two').verifyNativeSelection(),
      throwsA(isA<KeychainAccessGroupChanged>()),
    );
    await expectLater(
      guard('TEAM.two').recordNativeSelection(),
      throwsA(isA<KeychainAccessGroupChanged>()),
    );
  });

  test('malformed marker fails closed in either resolver direction', () {
    const fs = SecureFileSystem();
    fs.ensurePrivateDirSync('${root.path}/store');
    fs.writeAtomicSync(
      marker,
      Uint8List.fromList('not-a-keybay-marker'.codeUnits),
    );

    expect(() => guard('TEAM.one').verifyNativeSelection(),
        throwsA(isA<KeystoreOperationFailed>()));
    expect(
      () => MacOSSchemeGuard(
        appId: 'com.example.app',
        markerPath: marker,
      ).verifyFileSelection(),
      throwsA(isA<KeystoreOperationFailed>()),
    );
  });

  test('tracking backend records before a write mutation', () async {
    final delegate = _MemoryBackend();
    var recorded = false;
    final backend = SchemeTrackingBackend(
      backend: delegate,
      recordNativeSelection: () async => recorded = true,
    );

    await backend.write('k', Uint8List.fromList([1, 2, 3]));
    expect(recorded, isTrue);
    expect(await delegate.read('k'), [1, 2, 3]);
  });
}

final class _MemoryBackend implements AtomicDeleteAllBackend {
  final Map<String, Uint8List> _values = {};

  @override
  BackendCapabilities get capabilities =>
      const BackendCapabilities(enumeration: true, persistent: true);

  @override
  Future<Uint8List?> read(String key) async => _values[key];

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<void> write(String key, Uint8List value, {String? label}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> deleteAll() async => _values.clear();

  @override
  Future<Map<String, Uint8List>> readAll() async => Map.of(_values);

  @override
  Future<BackendInfo> describe() async => BackendInfo(
        scheme: StorageScheme.nativeItems,
        available: true,
        locked: false,
        capabilities: capabilities,
      );
}
