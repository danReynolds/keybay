@TestOn('mac-os')
@Tags(<String>['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/macos_login_keychain_root_store.dart';
import 'package:keybay/src/v2/macos_unentitled_host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late String canonicalFixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('keybay_v2_macos_host_');
    canonicalFixture = fixture.resolveSymbolicLinksSync();
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  Uri rootFor(String name) => Uri.directory('$canonicalFixture/$name');

  test('assembles one exact binding across files and protector', () async {
    final roots = _MemoryRootStore();
    final fileRoot = rootFor('binding');
    final host = await _host(root: fileRoot, roots: roots).resolve();

    expect(host.profile.code, macOSUnentitledProfileCode);
    expect(host.identity.stableValue, 'dev.keybay.macos-host-test');
    expect(identical(host.files.binding, host.binding), isTrue);
    expect(identical(host.protector.binding, host.binding), isTrue);
    expect(
      host.binding.domain,
      ResolvedApplicationBinding.derive(
        identity: host.identity,
        profile: host.profile,
        canonicalFileRoot: fileRoot,
      ).domain,
    );
    expect(Directory.fromUri(fileRoot).existsSync(), isFalse);
    roots.dispose();
  });

  test('refuses a non-macOS host and an entitled macOS process', () async {
    final roots = _MemoryRootStore();
    final identity = _identity();

    await expectLater(
      MacOSUnentitledHostPlatform.test(
        identity: identity,
        canonicalFileRoot: rootFor('wrong-os'),
        rootStore: roots,
        isMacOS: false,
      ).resolve(),
      throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
    );
    await expectLater(
      MacOSUnentitledHostPlatform.test(
        identity: identity,
        canonicalFileRoot: rootFor('entitled'),
        rootStore: roots,
        hasSignedApplicationIdentifier: true,
      ).resolve(),
      throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
    );
    expect(roots.itemCount, 0);
    roots.dispose();
  });

  test(
    'refuses an identity whose assurance belongs to another profile',
    () async {
      final roots = _MemoryRootStore();
      final identity = ApplicationIdentity(
        stableValue: 'dev.keybay.macos-host-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.osEnforced,
      );

      await expectLater(
        MacOSUnentitledHostPlatform.test(
          identity: identity,
          canonicalFileRoot: rootFor('wrong-assurance'),
          rootStore: roots,
        ).resolve(),
        throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
      );
      roots.dispose();
    },
  );

  test('same provider identity rejects a second candidate file root', () async {
    final roots = _MemoryRootStore();
    final first = V2StoreEngine(_host(root: rootFor('first'), roots: roots));
    final second = V2StoreEngine(_host(root: rootFor('second'), roots: roots));

    final initialized = await first.open();
    await initialized.close();
    await expectLater(
      second.open(),
      throwsA(_keybayFailure(KeybayErrorCode.storeStateConflict)),
    );
    expect(roots.itemCount, 1);

    await first.reset();
    roots.dispose();
  });

  test(
    'persists platform-only and passphrase-protected framed operations',
    () async {
      final roots = _MemoryRootStore();
      final fileRoot = rootFor('round-trip');
      final deriver = _FastPassphraseDeriver();
      final first = V2StoreEngine(
        _host(root: fileRoot, roots: roots),
        passphraseDeriver: deriver,
      );

      final initialized = await first.open();
      expect(initialized.wasInitialized, isTrue);
      await initialized.set('service/token', 'first');
      await initialized.setBytes(
        'service/binary',
        Uint8List.fromList(<int>[0, 1, 2, 255]),
      );
      final method = await initialized.auth.add(_credential('correct horse'));
      expect(method, isA<PassphraseMethod>());
      await initialized.close();

      final second = V2StoreEngine(
        _host(root: fileRoot, roots: roots),
        passphraseDeriver: deriver,
      );
      await expectLater(
        second.open(),
        throwsA(_keybayFailure(KeybayErrorCode.authRequired)),
      );
      await expectLater(
        second.open(credential: _credential('wrong phrase')),
        throwsA(_keybayFailure(KeybayErrorCode.unlockFailed)),
      );

      final reopened = await second.open(
        credential: _credential('correct horse'),
      );
      expect(reopened.wasInitialized, isFalse);
      expect(await reopened.get('service/token'), 'first');
      expect(await reopened.getBytes('service/binary'), <int>[0, 1, 2, 255]);
      await reopened.set('service/token', 'second');
      expect(await reopened.get('service/token'), 'second');
      await reopened.close();

      await second.reset();
      expect(roots.itemCount, 0);
      expect(
        File(
          '${Directory.fromUri(fileRoot).path}/keybay.v2.store',
        ).existsSync(),
        isFalse,
      );
      roots.dispose();
    },
  );
}

MacOSUnentitledHostPlatform _host({
  required Uri root,
  required _MemoryRootStore roots,
}) => MacOSUnentitledHostPlatform.test(
  identity: _identity(),
  canonicalFileRoot: root,
  rootStore: roots,
);

ApplicationIdentity _identity() => ApplicationIdentity(
  stableValue: 'dev.keybay.macos-host-test',
  source: ApplicationIdentitySource.test,
  assurance: ApplicationIdentityAssurance.namespaceOnly,
);

PassphraseCredential _credential(String phrase) =>
    PassphraseCredential(phrase: Uint8List.fromList(utf8.encode(phrase)));

Matcher _platformFailure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

Matcher _keybayFailure(KeybayErrorCode code) =>
    isA<KeybayException>().having((failure) => failure.code, 'code', code);

final class _FastPassphraseDeriver implements V2PassphraseDeriver {
  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) async {
    if (profileId != v2FirstPassphraseProfile) {
      throw StateError('unexpected test KDF profile');
    }
    final input = Uint8List.fromList(<int>[profileId, ...passphrase, ...salt]);
    try {
      return Uint8List.fromList(const DartSha256().hashSync(input).bytes);
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }
}

final class _MemoryRootStore implements MacOSLoginKeychainRootStore {
  final Map<String, Uint8List> _items = <String, Uint8List>{};

  int get itemCount => _items.length;

  @override
  Future<bool> createIfAbsent(String providerAddress, Uint8List value) async {
    if (_items.containsKey(providerAddress)) return false;
    _items[providerAddress] = Uint8List.fromList(value);
    return true;
  }

  @override
  Future<Uint8List?> read(String providerAddress) async {
    final value = _items[providerAddress];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<bool> exists(String providerAddress) async =>
      _items.containsKey(providerAddress);

  @override
  Future<void> delete(String providerAddress) async {
    final value = _items.remove(providerAddress);
    value?.fillRange(0, value.length, 0);
  }

  void dispose() {
    for (final value in _items.values) {
      value.fillRange(0, value.length, 0);
    }
    _items.clear();
  }
}
