@TestOn('mac-os')
@Tags(<String>['unit'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/ffi/apple_host.dart';
import 'package:keybay/src/v2/apple_data_protection_host_platform.dart';
import 'package:keybay/src/v2/apple_data_protection_keychain_root_store.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:keybay/src/v2/posix_store_files.dart';
import 'package:keybay/src/v2/store_files.dart';
import 'package:test/test.dart';

import 'support/v2_test_keybay.dart';

void main() {
  late Directory fixture;
  late Uri supportRoot;

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('keybay_v2_apple_host_');
    supportRoot = Uri.directory(fixture.resolveSymbolicLinksSync());
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  test('iOS derives one private root from matching signed identifiers', () {
    final facts = _iosFacts(supportRoot);

    expect(facts.bundleIdentifier, 'dev.keybay.ios-test');
    expect(facts.applicationIdentifier, 'ABCDE12345.dev.keybay.ios-test');
    expect(
      facts.canonicalFileRoot,
      Uri.directory('${fixture.resolveSymbolicLinksSync()}/keybay-v2'),
    );
  });

  test('public Apple host bindings resolve one existing support directory', () {
    final support = AppleHostApi.macOS().applicationSupportDirectory();
    expect(support, startsWith('/'));
    expect(
      FileSystemEntity.typeSync(support, followLinks: false),
      FileSystemEntityType.directory,
    );
  });

  test('signed Info.plist identity bypasses localized overrides', () {
    final source = File('lib/src/ffi/apple_host.dart').readAsStringSync();
    expect(source, contains("'CFBundleGetInfoDictionary'"));
    expect(source, isNot(contains("'CFBundleGetValueForInfoDictionaryKey'")));
  });

  test('iOS host API never exposes the macOS SecTask path', () {
    expect(
      AppleHostApi.ios().macOSSignedApplicationIdentifier,
      throwsA(isA<AppleHostApiFailure>()),
    );
  });

  test('signed identifier must be the private prefix plus exact bundle id', () {
    for (final applicationIdentifier in <String>[
      'ABCDE12345.dev.keybay.other',
      'ABCDE12345.shared.dev.keybay.ios-test',
      '*.dev.keybay.ios-test',
      'dev.keybay.ios-test',
    ]) {
      expect(
        () => resolveIOSHostFacts(
          bundleIdentifier: 'dev.keybay.ios-test',
          applicationIdentifier: applicationIdentifier,
          applicationSupportRoot: supportRoot,
        ),
        throwsA(isA<ApplicationIdentityFailure>()),
      );
    }
  });

  test('iOS assembles one exact OS-enforced binding', () async {
    final roots = _MemoryRootStore();
    final facts = _iosFacts(supportRoot);
    prepareApplePrivateStoreRoot(facts.canonicalFileRoot);

    final host = await IOSHostPlatform.test(
      facts: facts,
      rootStore: roots,
    ).resolve();

    expect(host.profile.code, iosDataProtectionProfileCode);
    expect(host.identity.stableValue, 'ABCDE12345.dev.keybay.ios-test');
    expect(host.identity.source, ApplicationIdentitySource.operatingSystem);
    expect(host.identity.assurance, ApplicationIdentityAssurance.osEnforced);
    expect(host.files, isA<PosixStoreFiles>());
    expect(identical(host.files.binding, host.binding), isTrue);
    expect(identical(host.protector.binding, host.binding), isTrue);
    expect(
      host.binding.domain,
      ResolvedApplicationBinding.forApplicationContainer(
        identity: host.identity,
        profile: host.profile,
        canonicalFileRoot: facts.canonicalFileRoot,
        containerRelativeRoot: Uri.parse(
          'Library/Application%20Support/keybay-v2/',
        ),
      ).domain,
    );
    roots.dispose();
  });

  test('iOS profile never runs on a non-iOS host', () async {
    final roots = _MemoryRootStore();
    final facts = _iosFacts(supportRoot);
    prepareApplePrivateStoreRoot(facts.canonicalFileRoot);

    await expectLater(
      IOSHostPlatform.test(
        facts: facts,
        rootStore: roots,
        isIOS: false,
      ).resolve(),
      throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
    );
    expect(roots.itemCount, 0);
    roots.dispose();
  });

  test('macOS assembles one signed application provider profile', () async {
    final roots = _MemoryRootStore();
    final facts = _macOSFacts(supportRoot);
    prepareApplePrivateStoreRoot(facts.canonicalFileRoot);

    final host = await MacOSEntitledHostPlatform.test(
      facts: facts,
      rootStore: roots,
    ).resolve();

    expect(host.profile.code, macOSEntitledDataProtectionProfileCode);
    expect(host.identity.stableValue, 'ABCDE12345.dev.keybay.macos-test');
    expect(host.identity.assurance, ApplicationIdentityAssurance.osEnforced);
    expect(identical(host.files.binding, host.binding), isTrue);
    expect(identical(host.protector.binding, host.binding), isTrue);
    roots.dispose();
  });

  test(
    'same signed macOS identity refuses a sandbox-mode path transition',
    () async {
      final roots = _MemoryRootStore();
      final otherSupport = Directory.systemTemp.createTempSync(
        'keybay_v2_macos_other_support_',
      );
      try {
        final sandboxedFacts = _macOSFacts(supportRoot);
        final unsandboxedFacts = _macOSFacts(
          Uri.directory(otherSupport.resolveSymbolicLinksSync()),
        );
        prepareApplePrivateStoreRoot(sandboxedFacts.canonicalFileRoot);
        prepareApplePrivateStoreRoot(unsandboxedFacts.canonicalFileRoot);

        final sandboxedHost = await MacOSEntitledHostPlatform.test(
          facts: sandboxedFacts,
          rootStore: roots,
        ).resolve();
        final unsandboxedHost = await MacOSEntitledHostPlatform.test(
          facts: unsandboxedFacts,
          rootStore: roots,
        ).resolve();
        expect(
          sandboxedHost.binding.providerAddress,
          unsandboxedHost.binding.providerAddress,
        );
        expect(
          sandboxedHost.binding.domain,
          isNot(unsandboxedHost.binding.domain),
        );

        final initialized = await V2StoreEngine(
          MacOSEntitledHostPlatform.test(
            facts: sandboxedFacts,
            rootStore: roots,
          ),
        ).open();
        await initialized.close();

        await expectLater(
          V2StoreEngine(
            MacOSEntitledHostPlatform.test(
              facts: unsandboxedFacts,
              rootStore: roots,
            ),
          ).open(),
          throwsA(
            isA<KeybayException>().having(
              (failure) => failure.code,
              'code',
              KeybayErrorCode.storeStateConflict,
            ),
          ),
        );
      } finally {
        if (otherSupport.existsSync()) otherSupport.deleteSync(recursive: true);
        roots.dispose();
      }
    },
  );

  test('macOS entitled profile never downgrades on a non-macOS host', () async {
    final roots = _MemoryRootStore();
    final facts = _macOSFacts(supportRoot);
    prepareApplePrivateStoreRoot(facts.canonicalFileRoot);

    await expectLater(
      MacOSEntitledHostPlatform.test(
        facts: facts,
        rootStore: roots,
        isMacOS: false,
      ).resolve(),
      throwsA(_platformFailure(PlatformProtectorFailureCode.unavailable)),
    );
    expect(roots.itemCount, 0);
    roots.dispose();
  });

  test(
    'assembled iOS store performs framed operations and exact reset',
    () async {
      final roots = _MemoryRootStore();
      final facts = _iosFacts(supportRoot);
      prepareApplePrivateStoreRoot(facts.canonicalFileRoot);
      final engine = V2StoreEngine(
        IOSHostPlatform.test(facts: facts, rootStore: roots),
      );

      final initialized = await engine.open();
      await initialized.set('service/token', 'secret');
      expect(await initialized.get('service/token'), 'secret');
      await initialized.close();

      final reopened = await engine.open();
      expect(reopened.wasInitialized, isFalse);
      expect(await reopened.get('service/token'), 'secret');
      await reopened.close();

      await engine.reset();
      expect(roots.itemCount, 0);
      expect(
        File(
          '${Directory.fromUri(facts.canonicalFileRoot).path}/keybay.v2.store',
        ).existsSync(),
        isFalse,
      );
      roots.dispose();
    },
  );

  test(
    'iOS preserves records and passphrase after container relocation',
    () async {
      final roots = _MemoryRootStore();
      addTearDown(roots.dispose);
      final before = Directory('${fixture.path}/container-before');
      final beforeSupport = Directory(
        '${before.path}/Library/Application Support',
      )..createSync(recursive: true);
      final firstFacts = _iosFacts(
        Uri.directory(beforeSupport.resolveSymbolicLinksSync()),
      );
      prepareApplePrivateStoreRoot(firstFacts.canonicalFileRoot);
      final first = V2StoreEngine(
        IOSHostPlatform.test(facts: firstFacts, rootStore: roots),
        passphraseDeriver: FastTestPassphraseDeriver(),
      );
      final phrase = Uint8List.fromList([1, 3, 5, 7, 9]);
      final credential = PassphraseCredential(phrase: phrase);
      addTearDown(() => phrase.fillRange(0, phrase.length, 0));
      final initialized = await first.open();
      addTearDown(initialized.close);
      await initialized.set('service/token', 'retained-secret');
      await initialized.set('other/value', 'retained-value');
      final method = await initialized.auth.add(credential);
      await initialized.close();

      // iOS can move the whole data container during an app update. Preserve
      // every managed file and the same provider; resolve the new OS location.
      final after = before.renameSync('${fixture.path}/container-after');
      final secondFacts = _iosFacts(
        Uri.directory(
          '${after.resolveSymbolicLinksSync()}/Library/Application Support',
        ),
      );
      prepareApplePrivateStoreRoot(secondFacts.canonicalFileRoot);
      final second = V2StoreEngine(
        IOSHostPlatform.test(facts: secondFacts, rootStore: roots),
        passphraseDeriver: FastTestPassphraseDeriver(),
      );
      final reopened = await second.open(credential: credential);
      addTearDown(reopened.close);
      expect(reopened.wasInitialized, isFalse);
      expect(await reopened.get('service/token'), 'retained-secret');
      expect(await reopened.get('other/value'), 'retained-value');
      expect(await reopened.listKeys(), ['other/value', 'service/token']);
      expect((await reopened.auth.list()).single.id, method.id);
      expect(roots.itemCount, 1);
      await reopened.close();

      final otherApp = V2StoreEngine(
        IOSHostPlatform.test(
          facts: resolveIOSHostFacts(
            bundleIdentifier: 'dev.keybay.other-ios-test',
            applicationIdentifier: 'ABCDE12345.dev.keybay.other-ios-test',
            applicationSupportRoot: Uri.directory(
              '${after.resolveSymbolicLinksSync()}/Library/Application Support',
            ),
          ),
          rootStore: roots,
        ),
        passphraseDeriver: FastTestPassphraseDeriver(),
      );
      await expectLater(
        otherApp.open(credential: credential),
        throwsA(
          isA<KeybayException>().having(
            (failure) => failure.code,
            'code',
            KeybayErrorCode.platformKeyInvalidated,
          ),
        ),
      );
      expect(roots.itemCount, 1);
      await expectLater(
        second.open(),
        throwsA(
          isA<KeybayException>().having(
            (failure) => failure.code,
            'code',
            KeybayErrorCode.authRequired,
          ),
        ),
      );
      await second.reset();
      expect(roots.itemCount, 0);
    },
  );

  test(
    'container binding still rejects a different physical POSIX root',
    () async {
      final roots = _MemoryRootStore();
      addTearDown(roots.dispose);
      final facts = _iosFacts(supportRoot);
      prepareApplePrivateStoreRoot(facts.canonicalFileRoot);
      final host = await IOSHostPlatform.test(
        facts: facts,
        rootStore: roots,
      ).resolve();
      final otherRoot = Uri.directory('${fixture.path}/other-store');
      prepareApplePrivateStoreRoot(otherRoot);
      expect(
        () => PosixStoreFiles.fromExistingPrivateRoot(
          binding: host.binding,
          canonicalFileRoot: otherRoot,
        ),
        throwsArgumentError,
      );
      expect(
        () => PosixStoreFiles(
          binding: host.binding,
          canonicalFileRoot: otherRoot,
        ),
        throwsArgumentError,
      );
    },
  );

  test('same signed iOS identity refuses an empty second container', () async {
    final roots = _MemoryRootStore();
    final firstFacts = _iosFacts(supportRoot);
    prepareApplePrivateStoreRoot(firstFacts.canonicalFileRoot);
    final secondSupport = Directory.systemTemp.createTempSync(
      'keybay_v2_apple_second_support_',
    );
    try {
      final secondFacts = _iosFacts(
        Uri.directory(secondSupport.resolveSymbolicLinksSync()),
      );
      prepareApplePrivateStoreRoot(secondFacts.canonicalFileRoot);
      final first = V2StoreEngine(
        IOSHostPlatform.test(facts: firstFacts, rootStore: roots),
      );
      final second = V2StoreEngine(
        IOSHostPlatform.test(facts: secondFacts, rootStore: roots),
      );

      final initialized = await first.open();
      await initialized.close();
      await expectLater(
        second.open(),
        throwsA(
          isA<KeybayException>().having(
            (failure) => failure.code,
            'code',
            KeybayErrorCode.storeStateConflict,
          ),
        ),
      );
      await first.reset();
    } finally {
      if (secondSupport.existsSync()) {
        secondSupport.deleteSync(recursive: true);
      }
      roots.dispose();
    }
  });

  test(
    'private root refuses missing-parent, occupied, symlink, and loose roots',
    () {
      expect(
        () => prepareApplePrivateStoreRoot(
          Uri.directory('${fixture.path}/missing-parent/store'),
        ),
        throwsA(isA<StoreFilesFailure>()),
      );

      final occupied = File(
        '${fixture.resolveSymbolicLinksSync()}/not-a-directory',
      )..writeAsStringSync('occupied');
      final fileRoot = Uri.directory(occupied.path);
      expect(
        () => prepareApplePrivateStoreRoot(fileRoot),
        throwsA(isA<StoreFilesFailure>()),
      );

      final target = Directory('${fixture.path}/target')..createSync();
      _chmod('0700', target.path);
      final symlink = Link('${fixture.path}/symlink')..createSync(target.path);
      expect(
        () => prepareApplePrivateStoreRoot(Uri.directory(symlink.path)),
        throwsA(isA<StoreFilesFailure>()),
      );

      final loose = Directory('${fixture.path}/loose')..createSync();
      _chmod('0755', loose.path);
      expect(
        () => prepareApplePrivateStoreRoot(Uri.directory(loose.path)),
        throwsA(isA<StoreFilesFailure>()),
      );
    },
  );
}

void _chmod(String mode, String path) {
  final result = Process.runSync('chmod', <String>[mode, path]);
  if (result.exitCode != 0) fail('chmod failed for a disposable fixture');
}

IOSHostFacts _iosFacts(Uri supportRoot) => resolveIOSHostFacts(
  bundleIdentifier: 'dev.keybay.ios-test',
  applicationIdentifier: 'ABCDE12345.dev.keybay.ios-test',
  applicationSupportRoot: supportRoot,
);

MacOSEntitledHostFacts _macOSFacts(Uri supportRoot) =>
    resolveMacOSEntitledHostFacts(
      bundleIdentifier: 'dev.keybay.macos-test',
      applicationIdentifier: 'ABCDE12345.dev.keybay.macos-test',
      applicationSupportRoot: supportRoot,
    );

Matcher _platformFailure(PlatformProtectorFailureCode code) =>
    isA<PlatformProtectorFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

final class _MemoryRootStore implements DataProtectionKeychainRootStore {
  final Map<String, Uint8List> _items = <String, Uint8List>{};

  int get itemCount => _items.length;

  @override
  Future<bool> createIfAbsent(String providerAddress, Uint8List value) async {
    if (_items.containsKey(providerAddress)) return false;
    _items[providerAddress] = Uint8List.fromList(value);
    return true;
  }

  @override
  Future<void> delete(String providerAddress) async {
    final removed = _items.remove(providerAddress);
    removed?.fillRange(0, removed.length, 0);
  }

  @override
  Future<bool> exists(String providerAddress) async =>
      _items.containsKey(providerAddress);

  @override
  Future<Uint8List?> read(String providerAddress) async {
    final value = _items[providerAddress];
    return value == null ? null : Uint8List.fromList(value);
  }

  void dispose() {
    for (final value in _items.values) {
      value.fillRange(0, value.length, 0);
    }
    _items.clear();
  }
}
