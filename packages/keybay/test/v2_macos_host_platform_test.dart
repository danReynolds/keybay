@Tags(<String>['unit'])
library;

import 'package:keybay/src/ffi/apple_host.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/macos_host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

void main() {
  test(
    'qualification selects exact signed identity without reading groups',
    () {
      const identifier = 'ABCDE12345.dev.keybay.test';
      for (final values in <(String?, String?)>[
        (identifier, null),
        (null, identifier),
        (identifier, identifier),
      ]) {
        expect(
          resolveMacOSSignedApplicationIdentifier(
            readIdentifier: (name) => name == 'com.apple.application-identifier'
                ? values.$1
                : values.$2,
            hasKeychainAccessGroups: () =>
                throw StateError('shared groups cannot select the identity'),
          ),
          identifier,
        );
      }
    },
  );

  test('qualification requires all signed keychain evidence to be absent', () {
    var groupChecks = 0;
    expect(
      resolveMacOSSignedApplicationIdentifier(
        readIdentifier: (_) => null,
        hasKeychainAccessGroups: () {
          groupChecks += 1;
          return false;
        },
      ),
      isNull,
    );
    expect(groupChecks, 1);
  });

  test(
    'malformed and conflicting signed identifiers cannot select a profile',
    () async {
      for (final values in <(String?, String?)>[
        ('', null),
        (null, ''),
        ('ABCDE12345.dev.keybay.test', 'ABCDE12345.dev.keybay.other'),
      ]) {
        await _expectQualificationFailure(
          () => resolveMacOSSignedApplicationIdentifier(
            readIdentifier: (name) => name == 'com.apple.application-identifier'
                ? values.$1
                : values.$2,
            hasKeychainAccessGroups: () => false,
          ),
        );
      }
    },
  );

  test(
    'group-only signed state cannot downgrade to unentitled storage',
    () async {
      await _expectQualificationFailure(
        () => resolveMacOSSignedApplicationIdentifier(
          readIdentifier: (_) => null,
          hasKeychainAccessGroups: () => true,
        ),
      );
    },
  );

  test(
    'unreadable native entitlement evidence cannot select either profile',
    () async {
      for (final unavailable in <String>[
        'com.apple.application-identifier',
        'application-identifier',
        'keychain-access-groups',
      ]) {
        await _expectQualificationFailure(
          () => resolveMacOSSignedApplicationIdentifier(
            readIdentifier: (name) =>
                name == unavailable ? throw const AppleHostApiFailure() : null,
            hasKeychainAccessGroups: () => throw const AppleHostApiFailure(),
          ),
        );
      }
    },
  );

  test(
    'signed application identifier selects only the entitled profile',
    () async {
      final selected = _RecordingHostPlatform();
      final rejected = _RecordingHostPlatform();
      final failure = Object();
      selected.failure = failure;

      await expectLater(
        MacOSHostPlatform.test(
          signedApplicationIdentifier: () => 'ABCDE12345.dev.keybay.test',
          entitled: selected,
          unentitled: rejected,
        ).resolve(),
        throwsA(same(failure)),
      );

      expect(selected.calls, 1);
      expect(rejected.calls, 0);
    },
  );

  test(
    'genuinely absent application identifier selects unentitled profile',
    () async {
      final selected = _RecordingHostPlatform();
      final rejected = _RecordingHostPlatform();
      final failure = Object();
      selected.failure = failure;

      await expectLater(
        MacOSHostPlatform.test(
          signedApplicationIdentifier: () => null,
          entitled: rejected,
          unentitled: selected,
        ).resolve(),
        throwsA(same(failure)),
      );

      expect(selected.calls, 1);
      expect(rejected.calls, 0);
    },
  );

  test('probe failure cannot downgrade to the unentitled profile', () async {
    final entitled = _RecordingHostPlatform();
    final unentitled = _RecordingHostPlatform();

    await expectLater(
      MacOSHostPlatform.test(
        signedApplicationIdentifier: () => throw StateError('probe failed'),
        entitled: entitled,
        unentitled: unentitled,
      ).resolve(),
      throwsA(
        isA<ApplicationIdentityFailure>().having(
          (failure) => failure.code,
          'code',
          ApplicationIdentityFailureCode.unavailable,
        ),
      ),
    );

    expect(entitled.calls, 0);
    expect(unentitled.calls, 0);
  });

  test('non-macOS host probes and opens neither profile', () async {
    final entitled = _RecordingHostPlatform();
    final unentitled = _RecordingHostPlatform();
    var probed = false;

    await expectLater(
      MacOSHostPlatform.test(
        signedApplicationIdentifier: () {
          probed = true;
          return null;
        },
        entitled: entitled,
        unentitled: unentitled,
        isMacOS: false,
      ).resolve(),
      throwsA(
        isA<PlatformProtectorFailure>().having(
          (failure) => failure.code,
          'code',
          PlatformProtectorFailureCode.unavailable,
        ),
      ),
    );

    expect(probed, isFalse);
    expect(entitled.calls, 0);
    expect(unentitled.calls, 0);
  });
}

Future<void> _expectQualificationFailure(String? Function() probe) async {
  final entitled = _RecordingHostPlatform();
  final unentitled = _RecordingHostPlatform();
  await expectLater(
    MacOSHostPlatform.test(
      signedApplicationIdentifier: probe,
      entitled: entitled,
      unentitled: unentitled,
    ).resolve(),
    throwsA(isA<ApplicationIdentityFailure>()),
  );
  expect(entitled.calls, 0);
  expect(unentitled.calls, 0);
}

final class _RecordingHostPlatform implements HostPlatform {
  int calls = 0;
  Object? failure;

  @override
  Future<ResolvedHost> resolve() {
    calls += 1;
    return Future<ResolvedHost>.error(failure ?? StateError('unexpected'));
  }
}
