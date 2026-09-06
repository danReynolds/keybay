@TestOn('mac-os || linux')
@Tags(<String>['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/linux_desktop_host_platform.dart';
import 'package:keybay/src/v2/linux_secret_service_root_store.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late String canonicalFixture;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('keybay_v2_linux_host_');
    expect(Process.runSync('chmod', <String>['700', fixture.path]).exitCode, 0);
    canonicalFixture = fixture.resolveSymbolicLinksSync();
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  Uri rootFor(String name) => Uri.directory('$canonicalFixture/$name');

  test('assembles one exact namespace-only binding', () async {
    final roots = _MemoryRootStore();
    final fileRoot = rootFor('binding');
    final host = await _host(root: fileRoot, roots: roots).resolve();

    expect(host.profile.code, linuxDesktopProfileCode);
    expect(host.identity.stableValue, 'dev.keybay.linux-host-test');
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

  test(
    'derives the file root from canonical XDG data home and identity',
    () async {
      final roots = _MemoryRootStore();
      final dataHome = Directory('$canonicalFixture/data')..createSync();
      final expected = _expectedRoot(dataHome.resolveSymbolicLinksSync());
      final host = await LinuxDesktopHostPlatform.test(
        identity: _identity(),
        rootStore: roots,
        environment: <String, String>{
          'XDG_DATA_HOME': dataHome.path,
          'HOME': '$canonicalFixture/ignored',
        },
      ).resolve();

      expect(
        host.binding.domain,
        ResolvedApplicationBinding.derive(
          identity: host.identity,
          profile: host.profile,
          canonicalFileRoot: expected,
        ).domain,
      );
      roots.dispose();
    },
  );

  test('a relative XDG data home is ignored in favor of HOME', () async {
    final roots = _MemoryRootStore();
    final home = Directory('$canonicalFixture/home')..createSync();
    final dataHome = Directory('${home.path}/.local/share')
      ..createSync(recursive: true);
    final expected = _expectedRoot(dataHome.resolveSymbolicLinksSync());
    final host = await LinuxDesktopHostPlatform.test(
      identity: _identity(),
      rootStore: roots,
      environment: <String, String>{
        'XDG_DATA_HOME': 'relative/data',
        'HOME': home.path,
      },
    ).resolve();

    expect(
      host.binding.domain,
      ResolvedApplicationBinding.derive(
        identity: host.identity,
        profile: host.profile,
        canonicalFileRoot: expected,
      ).domain,
    );
    roots.dispose();
  });

  test('securely prepares a missing clean-account data hierarchy', () async {
    final roots = _MemoryRootStore();
    final home = Directory('$canonicalFixture/clean-home')..createSync();
    expect(Process.runSync('chmod', <String>['700', home.path]).exitCode, 0);
    final expectedDataHome = '${home.path}/.local/share';
    expect(Directory(expectedDataHome).existsSync(), isFalse);

    final host = await LinuxDesktopHostPlatform.test(
      identity: _identity(),
      rootStore: roots,
      environment: <String, String>{'HOME': home.path},
    ).resolve();

    expect(Directory(expectedDataHome).existsSync(), isTrue);
    expect(FileStat.statSync('${home.path}/.local').mode & 0x1ff, 0x1c0);
    expect(FileStat.statSync(expectedDataHome).mode & 0x1ff, 0x1c0);
    expect(
      host.binding.domain,
      ResolvedApplicationBinding.derive(
        identity: host.identity,
        profile: host.profile,
        canonicalFileRoot: _expectedRoot(expectedDataHome),
      ).domain,
    );
    roots.dispose();
  });

  test('canonicalizes a pre-existing XDG data-home symlink', () async {
    final roots = _MemoryRootStore();
    final target = Directory('$canonicalFixture/actual-data')..createSync();
    final link = Link('$canonicalFixture/data-link')..createSync(target.path);
    final canonicalTarget = target.resolveSymbolicLinksSync();

    final host = await LinuxDesktopHostPlatform.test(
      identity: _identity(),
      rootStore: roots,
      environment: <String, String>{'XDG_DATA_HOME': link.path},
    ).resolve();

    expect(
      host.binding.domain,
      ResolvedApplicationBinding.derive(
        identity: host.identity,
        profile: host.profile,
        canonicalFileRoot: _expectedRoot(canonicalTarget),
      ).domain,
    );
    roots.dispose();
  });

  test('rejects dot segments and a non-directory XDG data home', () async {
    final roots = _MemoryRootStore();
    final dataFile = File('$canonicalFixture/not-a-directory')
      ..writeAsStringSync('not a directory');

    for (final dataHome in <String>[
      '$canonicalFixture/./data',
      '$canonicalFixture/parent/../data',
      dataFile.path,
    ]) {
      await expectLater(
        LinuxDesktopHostPlatform.test(
          identity: _identity(),
          rootStore: roots,
          environment: <String, String>{'XDG_DATA_HOME': dataHome},
        ).resolve(),
        throwsA(_storeFailure(StoreFilesFailureCode.operationFailed)),
      );
    }
    roots.dispose();
  });

  test(
    'refuses another OS, confined Linux, and stronger identity assurance',
    () async {
      // KB-INV-006: confinement never downgrades into ordinary Secret Service.
      final roots = _MemoryRootStore();
      await expectLater(
        LinuxDesktopHostPlatform.test(
          identity: _identity(),
          rootStore: roots,
          canonicalFileRoot: rootFor('wrong-os'),
          isLinux: false,
        ).resolve(),
        throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
      );
      for (final hint in <String, String>{
        'SNAP': '$canonicalFixture/snap',
        'SNAP_NAME': 'dev-keybay-test',
      }.entries) {
        await expectLater(
          LinuxDesktopHostPlatform.test(
            identity: _identity(),
            rootStore: roots,
            canonicalFileRoot: rootFor('snap-${hint.key.toLowerCase()}'),
            environment: <String, String>{hint.key: hint.value},
          ).resolve(),
          throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
        );
      }
      await expectLater(
        LinuxDesktopHostPlatform.test(
          identity: _identity(),
          rootStore: roots,
          canonicalFileRoot: rootFor('flatpak'),
          isFlatpak: true,
        ).resolve(),
        throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
      );
      await expectLater(
        LinuxDesktopHostPlatform.test(
          identity: ApplicationIdentity(
            stableValue: 'dev.keybay.linux-host-test',
            source: ApplicationIdentitySource.test,
            assurance: ApplicationIdentityAssurance.osEnforced,
          ),
          rootStore: roots,
          canonicalFileRoot: rootFor('wrong-assurance'),
        ).resolve(),
        throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
      );
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );

  test('recognizes only snapd AppArmor security-tag prefixes', () {
    for (final label in <String>[
      'snap.example.app (enforce)',
      'snap.example.hook.install (complain)',
      'snap.example_component.app',
    ]) {
      expect(
        linuxAppArmorLabelIdentifiesSnap(utf8.encode(label)),
        isTrue,
        reason: label,
      );
    }
    for (final label in <String>[
      'unconfined',
      'docker-default (enforce)',
      'snap-update-ns.example (enforce)',
      ' snap.example.app (enforce)',
      'snap',
    ]) {
      expect(
        linuxAppArmorLabelIdentifiesSnap(utf8.encode(label)),
        isFalse,
        reason: label,
      );
    }
  });

  test(
    'identity resolution failure reaches the public error unchanged',
    () async {
      final roots = _MemoryRootStore();
      final engine = V2StoreEngine(
        LinuxDesktopHostPlatform.test(
          identityResolver: () async => throw const ApplicationIdentityFailure(
            ApplicationIdentityFailureCode.unavailable,
          ),
          rootStore: roots,
          canonicalFileRoot: rootFor('identity-failure'),
        ),
      );

      await expectLater(
        engine.open(),
        throwsA(_keybayFailure(KeybayErrorCode.applicationIdentityUnavailable)),
      );
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );

  test('provider creation-lock contention reaches public storeBusy', () async {
    final roots = _MemoryRootStore()
      ..nextFailure = const LinuxSecretServiceProviderBusy();
    final engine = V2StoreEngine(
      _host(root: rootFor('provider-busy'), roots: roots),
    );

    await expectLater(
      engine.open(),
      throwsA(_keybayFailure(KeybayErrorCode.storeBusy)),
    );
    roots.dispose();
  });

  test('same provider identity rejects a second XDG data root', () async {
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
      await initialized.auth.add(_credential('correct horse'));
      await initialized.close();

      final second = V2StoreEngine(
        _host(root: fileRoot, roots: roots),
        passphraseDeriver: deriver,
      );
      await expectLater(
        second.open(),
        throwsA(_keybayFailure(KeybayErrorCode.authRequired)),
      );
      final reopened = await second.open(
        credential: _credential('correct horse'),
      );
      expect(await reopened.get('service/token'), 'first');
      expect(await reopened.getBytes('service/binary'), <int>[0, 1, 2, 255]);
      await reopened.close();

      await second.reset();
      expect(roots.itemCount, 0);
      roots.dispose();
    },
  );
}

LinuxDesktopHostPlatform _host({
  required Uri root,
  required _MemoryRootStore roots,
}) => LinuxDesktopHostPlatform.test(
  identity: _identity(),
  canonicalFileRoot: root,
  rootStore: roots,
);

ApplicationIdentity _identity() => ApplicationIdentity(
  stableValue: 'dev.keybay.linux-host-test',
  source: ApplicationIdentitySource.test,
  assurance: ApplicationIdentityAssurance.namespaceOnly,
);

Uri _expectedRoot(String dataHome) {
  final identity = _identity();
  final digest = const DartSha256()
      .hashSync(
        utf8.encode(
          'keybay:v2:linux-desktop:file-root\u0000'
          '${identity.assurance.wireCode}\u0000'
          '$linuxDesktopProfileCode\u0000'
          '${identity.stableValue}',
        ),
      )
      .bytes;
  final suffix = digest
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return Uri.directory('$dataHome/${identity.stableValue}-$suffix.keybay-v2');
}

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

Matcher _storeFailure(StoreFilesFailureCode code) =>
    isA<StoreFilesFailure>().having((failure) => failure.code, 'code', code);

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

final class _MemoryRootStore implements LinuxSecretServiceRootStore {
  final Map<String, Uint8List> _items = <String, Uint8List>{};
  Exception? nextFailure;

  int get itemCount => _items.length;

  @override
  Future<void> createNew(String providerAddress, Uint8List value) async {
    if (_items.containsKey(providerAddress)) {
      throw const LinuxSecretServiceMultipleMatches();
    }
    _items[providerAddress] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(LinuxSecretServiceRoot root) async {
    if (root is! _MemoryRoot || !identical(root.owner, this)) {
      throw StateError('foreign root');
    }
    final value = _items[root.address];
    if (!identical(value, root.token)) throw StateError('stale root');
    _items.remove(root.address);
    value!.fillRange(0, value.length, 0);
  }

  @override
  Future<LinuxSecretServiceRoot?> readUnique(String providerAddress) async {
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    final value = _items[providerAddress];
    return value == null
        ? null
        : _MemoryRoot(
            owner: this,
            address: providerAddress,
            token: value,
            value: Uint8List.fromList(value),
          );
  }

  @override
  Future<T> withCreationLock<T>(
    String providerAddress,
    Future<T> Function() operation,
  ) => operation();

  void dispose() {
    for (final value in _items.values) {
      value.fillRange(0, value.length, 0);
    }
    _items.clear();
  }
}

final class _MemoryRoot implements LinuxSecretServiceRoot {
  _MemoryRoot({
    required this.owner,
    required this.address,
    required this.token,
    required this.value,
  });

  final _MemoryRootStore owner;
  final String address;
  final Uint8List token;

  @override
  final Uint8List value;
}
