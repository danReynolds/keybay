@Tags(['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_crypto.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2StoreEngine, V2StoreSession, debugStoreSessionKeyIsCleared;
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_passkey_backend.dart';
import 'support/v2_pinned_store_files.dart';
import 'support/v2_platform_fakes.dart';
import 'support/v2_test_keybay.dart';

const _rpId = 'vault.example.com';

void main() {
  for (final route in PasskeyRoute.values) {
    test(
      '$route creation and exact reopen retain mandatory platform root',
      () async {
        final env = _Environment();
        addTearDown(env.dispose);
        final created = await env.open(credential: _passkey(route));
        expect(created.wasInitialized, isTrue);
        await created.set('service/token', 'test value');
        final method = (await created.auth.list()).single as PasskeyMethod;
        expect(method.route, route);
        expect(method.rpId, _rpId);
        expect(method.label, 'Primary');
        expect(env.provider.operationCount, 1);
        expect(env.provider.evaluations, hasLength(2));
        env.provider.expectReleased();
        await created.close();

        final before = await _copyLive(env.files);
        final required = await _failure(
          env.open(),
          KeybayErrorCode.authRequired,
        );
        expect(required.authMethods.map((method) => method.id), [method.id]);
        expect(env.provider.operationCount, 1);
        expect(await _copyLive(env.files), before);

        final reopened = await env.open(
          credential: _passkey(route, methodId: method.id),
          freshEngine: true,
        );
        expect(reopened.wasInitialized, isFalse);
        expect(await reopened.get('service/token'), 'test value');
        expect(env.provider.evaluations.last.authenticatorState.signCount, 2);
        env.provider.expectReleased();
        await reopened.close();

        final reset = await env.protector.prepareReset(
          interaction: PlatformInteraction.forbidden,
        );
        try {
          await reset.commit();
        } finally {
          await reset.close();
        }
        final protectedBytes = await _copyLive(env.files);
        final operations = env.provider.operationCount;
        await _failure(
          env.open(credential: _passkey(route, methodId: method.id)),
          KeybayErrorCode.platformKeyInvalidated,
        );
        expect(env.provider.operationCount, operations);
        expect(await _copyLive(env.files), protectedBytes);
      },
    );
  }

  test(
    'mixed auth rotation preserves survivors without requesting their secrets',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _phrase());
      await _writeRecords(owner);
      final phrase = (await owner.auth.list()).single as PassphraseMethod;
      var peer = await env.open(credential: _phrase());
      var before = await _copyLive(env.files);

      final system =
          await owner.auth.add(_passkey(PasskeyRoute.system)) as PasskeyMethod;
      _expectResealed(before, await _copyLive(env.files));
      await _expectStale(peer);
      expect(env.provider.operationCount, 1);
      env.provider.expectReleased();

      peer = await env.open(credential: _phrase());
      before = await _copyLive(env.files);
      final hardware =
          await owner.auth.add(_passkey(PasskeyRoute.hardware))
              as PasskeyMethod;
      _expectResealed(before, await _copyLive(env.files));
      await _expectStale(peer);
      expect(
        env.provider.operationCount,
        2,
        reason: 'Adding hardware must not recover the surviving system key.',
      );
      expect(
        (await owner.auth.list()).map((method) => method.id),
        unorderedEquals([phrase.id, system.id, hardware.id]),
      );
      await _expectRecords(
        await env.open(credential: _phrase(), freshEngine: true),
      );
      await _expectRecords(
        await env.open(
          credential: _passkey(PasskeyRoute.system, methodId: system.id),
          freshEngine: true,
        ),
      );

      peer = await env.open(credential: _phrase());
      before = await _copyLive(env.files);
      final previousOperations = env.provider.operationCount;
      final replacement =
          await owner.auth.update(
                _passkey(
                  PasskeyRoute.system,
                  rpId: 'replacement.example.com',
                  methodId: hardware.id,
                  label: 'Replacement',
                ),
              )
              as PasskeyMethod;
      expect(replacement.id, hardware.id);
      expect(replacement.rpId, 'replacement.example.com');
      expect(replacement.route, PasskeyRoute.system);
      expect(replacement.label, 'Replacement');
      expect(env.provider.operationCount, previousOperations + 1);
      _expectResealed(before, await _copyLive(env.files));
      await _expectStale(peer);
      await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.hardware, methodId: hardware.id),
        ),
        KeybayErrorCode.protectionMismatch,
      );
      expect(env.provider.operationCount, previousOperations + 1);

      peer = await env.open(credential: _phrase());
      before = await _copyLive(env.files);
      final operationsBeforeRemove = env.provider.operationCount;
      await owner.auth.remove(system.id);
      expect(env.provider.operationCount, operationsBeforeRemove);
      _expectResealed(before, await _copyLive(env.files));
      await _expectStale(peer);
      await _expectRecords(
        await env.open(credential: _phrase(), freshEngine: true),
      );
      final survivor = await env.open(
        credential: _passkey(
          PasskeyRoute.system,
          rpId: replacement.rpId,
          methodId: replacement.id,
        ),
        freshEngine: true,
      );
      await _expectRecords(survivor);
      expect(
        (await survivor.auth.list()).map((method) => method.id),
        unorderedEquals([phrase.id, replacement.id]),
      );

      final operationsBeforeLastRemovals = env.provider.operationCount;
      await owner.auth.remove(phrase.id);
      await _failure(
        env.open(credential: _phrase()),
        KeybayErrorCode.protectionMismatch,
      );
      await owner.auth.remove(replacement.id);
      expect(env.provider.operationCount, operationsBeforeLastRemovals);
      expect(await owner.auth.list(), isEmpty);
      await _expectRecords(await env.open(freshEngine: true));
      env.provider.expectReleased();
    },
  );

  test(
    'selection uses exact ID or one compatible RP and route before prompts',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _phrase());
      final phrase = (await owner.auth.list()).single;
      final first = await owner.auth.add(_passkey(PasskeyRoute.system));
      final second = await owner.auth.add(_passkey(PasskeyRoute.system));
      final hardware = await owner.auth.add(_passkey(PasskeyRoute.hardware));
      final otherRp = await owner.auth.add(
        _passkey(PasskeyRoute.system, rpId: 'other.example.com'),
      );
      final before = await _copyLive(env.files);
      final operations = env.provider.operationCount;

      final required = await _failure(env.open(), KeybayErrorCode.authRequired);
      expect(
        required.authMethods.map((method) => method.id),
        unorderedEquals([
          phrase.id,
          first.id,
          second.id,
          hardware.id,
          otherRp.id,
        ]),
      );
      expect(required.authMethods.clear, throwsUnsupportedError);
      final selection = await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.system, rpId: 'VAULT.EXAMPLE.COM'),
        ),
        KeybayErrorCode.authMethodSelectionRequired,
      );
      expect(
        selection.authMethods.map((method) => method.id),
        unorderedEquals([first.id, second.id]),
      );
      expect(selection.authMethods.clear, throwsUnsupportedError);

      for (final request in [
        _passkey(PasskeyRoute.system, methodId: phrase.id),
        _passkey(PasskeyRoute.system, methodId: hardware.id),
        _passkey(PasskeyRoute.hardware, methodId: first.id),
        _passkey(PasskeyRoute.system, methodId: otherRp.id),
        _passkey(PasskeyRoute.system, rpId: 'missing.example.com'),
      ]) {
        await _failure(
          env.open(credential: request),
          KeybayErrorCode.protectionMismatch,
        );
      }
      await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.system, methodId: _missingId),
        ),
        KeybayErrorCode.authMethodNotConfigured,
      );
      expect(env.provider.operationCount, operations);
      expect(await _copyLive(env.files), before);

      final exact = await env.open(
        credential: _passkey(
          PasskeyRoute.system,
          rpId: 'VAULT.EXAMPLE.COM',
          methodId: first.id,
          label: 'An unlock label does not select another method',
        ),
      );
      expect(exact.wasInitialized, isFalse);
      expect(env.provider.operationCount, operations + 1);
      expect(env.provider.evaluations.last.credentialId.first, 1);
    },
  );

  test(
    'platform-only and passphrase stores reject passkey opens without enrolling',
    () async {
      for (final credential in <KeybayCredential?>[null, _phrase()]) {
        final env = _Environment();
        addTearDown(env.dispose);
        final original = await env.open(credential: credential);
        await original.set('service/token', 'retained');
        await original.close();
        final before = await _copyLive(env.files);
        for (final route in PasskeyRoute.values) {
          await _failure(
            env.open(credential: _passkey(route)),
            KeybayErrorCode.protectionMismatch,
          );
        }
        expect(env.provider.operationCount, 0);
        expect(await _copyLive(env.files), before);
        expect(
          await (await env.open(credential: credential)).get('service/token'),
          'retained',
        );
      }
    },
  );

  test(
    'malformed label fails before creating a passkey or platform root',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      await _failure(
        env.open(
          credential: _passkey(
            PasskeyRoute.system,
            label: String.fromCharCode(0xd800),
          ),
        ),
        KeybayErrorCode.invalidAuthInput,
      );
      expect(env.provider.operationCount, 0);
      expect(env.registry.rootCount, 0);
      expect(env.files.hasLiveFile, isFalse);
    },
  );

  test(
    'invalid method mutations fail before enrollment and preserve policy',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.system, methodId: _missingId),
        ),
        KeybayErrorCode.invalidAuthInput,
      );
      expect(env.files.hasLiveFile, isFalse);
      expect(env.registry.rootCount, 0);
      final owner = await env.open(credential: _phrase());
      final phrase = (await owner.auth.list()).single;
      final before = await _copyLive(env.files);
      await _failure(
        owner.auth.add(_passkey(PasskeyRoute.system, methodId: phrase.id)),
        KeybayErrorCode.invalidAuthInput,
      );
      await _failure(
        owner.auth.update(_passkey(PasskeyRoute.system)),
        KeybayErrorCode.invalidAuthInput,
      );
      await _failure(
        owner.auth.update(_passkey(PasskeyRoute.system, methodId: phrase.id)),
        KeybayErrorCode.protectionMismatch,
      );
      await _failure(
        owner.auth.update(_passkey(PasskeyRoute.system, methodId: _missingId)),
        KeybayErrorCode.authMethodNotConfigured,
      );
      await _failure(
        owner.auth.add(_phrase()),
        KeybayErrorCode.authMethodAlreadyConfigured,
      );
      expect(env.provider.operationCount, 0);
      expect(await _copyLive(env.files), before);
    },
  );

  test(
    'passkey open persists refreshed state before returning a usable session',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final created = await env.open(credential: _passkey(PasskeyRoute.system));
      await _writeRecords(created);
      final method = (await created.auth.list()).single;
      await created.close();
      expect(await _storedCounter(env, method.id), 2);
      final before = await _copyLive(env.files);

      final reopened = await env.open(
        credential: _passkey(PasskeyRoute.system),
        freshEngine: true,
      );
      expect(await _storedCounter(env, method.id), 3);
      expect(
        _frames(await _copyLive(env.files)),
        _frames(before),
        reason: 'Persisting provider state must preserve record ciphertext.',
      );
      await _expectRecords(reopened);
      expect((await reopened.auth.list()).single.id, method.id);
      await reopened.close();
      final third = await env.open(
        credential: _passkey(PasskeyRoute.system),
        freshEngine: true,
      );
      expect(env.provider.evaluations.last.authenticatorState.signCount, 3);
      expect(await _storedCounter(env, method.id), 4);
      await _expectRecords(third);
      env.provider.expectReleased();
    },
  );

  test(
    'record operations and auth listing do not invoke the passkey provider',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _passkey(PasskeyRoute.hardware));
      final operations = env.provider.operationCount;
      await owner.set('one', 'first');
      await owner.setBytes('two', Uint8List.fromList([2, 3]));
      expect(await owner.get('one'), 'first');
      expect(await owner.getBytes('two'), [2, 3]);
      expect(await owner.getManyBytes(['one', 'two', 'missing']), {
        'one': utf8.encode('first'),
        'two': [2, 3],
        'missing': null,
      });
      expect(await owner.contains('one'), isTrue);
      expect(await owner.listKeys(), ['one', 'two']);
      final methods = await owner.auth.list();
      expect(methods.single, isA<PasskeyMethod>());
      expect(methods.clear, throwsUnsupportedError);
      await owner.delete('one');
      await owner.clearAll();
      expect(await owner.listKeys(), isEmpty);
      expect(env.provider.operationCount, operations);
      env.provider.expectReleased();
    },
  );

  test(
    'wrong PRF output fails closed, clears result, and leaves counters on disk',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _passkey(PasskeyRoute.system));
      await owner.set('service/token', 'retained');
      final method = (await owner.auth.list()).single;
      await owner.close();
      final before = await _copyLive(env.files);
      env.files.hasTransactionArtifacts = true;
      env.provider.wrongNextSecret = true;

      await _failure(
        env.open(credential: _passkey(PasskeyRoute.system)),
        KeybayErrorCode.unlockFailed,
      );
      expect(await _copyLive(env.files), before);
      expect(await _storedCounter(env, method.id), 2);
      expect(env.files.hasTransactionArtifacts, isTrue);
      env.provider.expectReleased();
      final recovered = await env.open(
        credential: _passkey(PasskeyRoute.system),
      );
      expect(await recovered.get('service/token'), 'retained');
      expect(env.files.hasTransactionArtifacts, isFalse);
    },
  );

  test(
    'provider failure keeps its stable error code without weakening protection',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _passkey(PasskeyRoute.hardware));
      await owner.close();
      final before = await _copyLive(env.files);
      env.provider.nextFailure = PasskeyErrorCode.pinInvalid;
      final error = await _failure(
        env.open(credential: _passkey(PasskeyRoute.hardware)),
        KeybayErrorCode.passkeyOperationFailed,
      );
      expect(error.passkeyCode, PasskeyErrorCode.pinInvalid);
      expect(
        env.provider.registrations,
        hasLength(1),
        reason: 'Unlock failure must not create a replacement credential.',
      );
      expect(await _copyLive(env.files), before);
      env.provider.expectReleased();
    },
  );

  test(
    'platform-authenticated metadata is not trusted without manifest auth',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _passkey(PasskeyRoute.system));
      await owner.set('service/token', 'retained');
      final method = (await owner.auth.list()).single;
      await _forgeLabelWithPlatformRoot(env, 'Forged!');
      final tampered = await _copyLive(env.files);
      final operations = env.provider.operationCount;

      // A holder of the platform root can supply hints, but not a valid manifest.
      final hint = await _failure(env.open(), KeybayErrorCode.authRequired);
      expect((hint.authMethods.single as PasskeyMethod).label, 'Forged!');
      expect(env.provider.operationCount, operations);
      await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.system, methodId: method.id),
        ),
        KeybayErrorCode.storeAuthenticationFailed,
      );
      env.provider.expectReleased();
      final operationsAfterUnlock = env.provider.operationCount;
      await _failure(
        owner.auth.add(_passkey(PasskeyRoute.hardware)),
        KeybayErrorCode.storeAuthenticationFailed,
      );
      expect(
        env.provider.operationCount,
        operationsAfterUnlock,
        reason: 'Auth mutations authenticate the old directory before any UI.',
      );
      expect(await _copyLive(env.files), tampered);
    },
  );

  for (final freshEngine in [false, true]) {
    test(
      'counterless unlock rejects concurrent revocation (fresh engine: $freshEngine)',
      () async {
        final env = _Environment();
        addTearDown(env.dispose);
        env.provider.counterless = true;
        final owner = await env.open(credential: _passkey(PasskeyRoute.system));
        final passkey = (await owner.auth.list()).single;
        await owner.auth.add(_phrase());
        await owner.set('service/token', 'retained');
        final gate = _CeremonyGate();
        env.provider.afterNextSecret = gate.pause;
        final pending = _capture(
          env.open(
            credential: _passkey(PasskeyRoute.system),
            freshEngine: freshEngine,
          ),
        );
        await gate.entered.future;
        late Uint8List afterRemoval;
        try {
          await owner.auth.remove(passkey.id);
          afterRemoval = await _copyLive(env.files);
        } finally {
          gate.resume();
        }
        final result = await pending;
        expect(result, isA<KeybayException>());
        expect(
          (result! as KeybayException).code,
          freshEngine
              ? KeybayErrorCode.storeStateConflict
              : KeybayErrorCode.staleSession,
        );
        expect(await _copyLive(env.files), afterRemoval);
        expect((await owner.auth.list()).single, isA<PassphraseMethod>());
        expect(await owner.get('service/token'), 'retained');
        env.provider.expectReleased();
      },
    );
  }

  test(
    'interactive auth preparation releases lock and preserves newer record writes',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _phrase());
      await _writeRecords(owner);
      final writer = await env.open(credential: _phrase(), freshEngine: true);
      final gate = _CeremonyGate();
      env.provider.afterNextSecret = gate.pause;
      final pending = _capture(owner.auth.add(_passkey(PasskeyRoute.system)));
      await gate.entered.future;
      try {
        await writer.set('middle', 'newer');
        await writer.set('created-during-prompt', 'retained');
        expect(await writer.delete('alpha'), isTrue);
      } finally {
        gate.resume();
      }
      expect(await pending, isA<PasskeyMethod>());
      expect(await owner.get('middle'), 'newer');
      expect(await owner.get('created-during-prompt'), 'retained');
      expect(await owner.get('alpha'), isNull);
      expect(await owner.get('zulu'), 'final');
      expect(env.provider.registrations, hasLength(1));
      expect(env.provider.evaluations, hasLength(2));
      final reopened = await env.open(
        credential: _passkey(PasskeyRoute.system),
        freshEngine: true,
      );
      expect(await reopened.listKeys(), [
        'created-during-prompt',
        'middle',
        'zulu',
      ]);
      expect(await reopened.get('middle'), 'newer');
      env.provider.expectReleased();
    },
  );

  test(
    'interactive preparation conflicts with a concurrent auth policy change',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _phrase());
      await owner.set('service/token', 'retained');
      final peer = await env.open(credential: _phrase(), freshEngine: true);
      final gate = _CeremonyGate();
      env.provider.afterNextSecret = gate.pause;
      final pending = _capture(owner.auth.add(_passkey(PasskeyRoute.hardware)));
      await gate.entered.future;
      late Uint8List committed;
      try {
        await peer.auth.update(
          PassphraseCredential(phrase: Uint8List.fromList([9, 8, 7])),
        );
        committed = await _copyLive(env.files);
      } finally {
        gate.resume();
      }
      final result = await pending;
      expect(result, isA<KeybayException>());
      expect(
        (result! as KeybayException).code,
        KeybayErrorCode.storeStateConflict,
      );
      expect(await _copyLive(env.files), committed);
      expect(
        env.provider.registrations,
        hasLength(1),
        reason: 'A conflict must not silently run another ceremony.',
      );
      expect(env.provider.evaluations, hasLength(2));
      expect((await peer.auth.list()).single, isA<PassphraseMethod>());
      expect(await peer.get('service/token'), 'retained');
      await _failure(
        env.open(credential: _phrase()),
        KeybayErrorCode.unlockFailed,
      );
      final reopened = await env.open(
        credential: PassphraseCredential(phrase: Uint8List.fromList([9, 8, 7])),
        freshEngine: true,
      );
      expect(await reopened.get('service/token'), 'retained');
      env.provider.expectReleased();
    },
  );

  test(
    'callback reentrancy fails promptly while outer-zone queued work succeeds',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _phrase());
      await owner.set('service/token', 'retained');
      final gate = _CeremonyGate();
      env.provider.afterNextSecret = () async {
        await _failure(owner.get('service/token'), KeybayErrorCode.storeBusy);
        await _failure(owner.close(), KeybayErrorCode.storeBusy);
        await _failure(
          env.open(credential: _phrase()),
          KeybayErrorCode.storeBusy,
        );
        await _failure(env.engine.reset(), KeybayErrorCode.storeBusy);
        await gate.pause();
      };
      final pending = _capture(owner.auth.add(_passkey(PasskeyRoute.system)));
      await gate.entered.future;
      final queued = owner.get('service/token');
      gate.resume();
      expect(await pending, isA<PasskeyMethod>());
      expect(await queued, 'retained');
      expect(owner.isClosed, isFalse);
      expect(
        (await owner.auth.list()).whereType<PasskeyMethod>(),
        hasLength(1),
      );
      env.provider.expectReleased();
    },
  );

  test(
    'pre-cancelled enrollment creates no root, store, or native operation',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final cancellation = PasskeyCancellation()..cancel();
      final error = await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.system, cancellation: cancellation),
        ),
        KeybayErrorCode.passkeyOperationFailed,
      );
      expect(error.passkeyCode, PasskeyErrorCode.cancelled);
      expect(env.provider.operationCount, 0);
      expect(env.files.hasLiveFile, isFalse);
      expect(env.registry.rootCount, 0);
    },
  );

  test(
    'cancellation during assertion drains provider and preserves live state',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _passkey(PasskeyRoute.system));
      await owner.set('service/token', 'retained');
      await owner.close();
      final before = await _copyLive(env.files);
      final cancellation = PasskeyCancellation();
      env.provider.afterNextSecret = cancellation.cancel;
      final error = await _failure(
        env.open(
          credential: _passkey(PasskeyRoute.system, cancellation: cancellation),
        ),
        KeybayErrorCode.passkeyOperationFailed,
      );
      expect(error.passkeyCode, PasskeyErrorCode.cancelled);
      expect(await _copyLive(env.files), before);
      env.provider.expectReleased();
      expect(env.files.activeHandleCount, 0);
      final reopened = await env.open(
        credential: _passkey(PasskeyRoute.system),
      );
      expect(await reopened.get('service/token'), 'retained');
    },
  );

  test(
    'cancellation after enrollment result release prevents auth commit',
    () async {
      final env = _Environment();
      addTearDown(env.dispose);
      final owner = await env.open(credential: _phrase());
      await _writeRecords(owner);
      final peer = await env.open(credential: _phrase());
      final before = await _copyLive(env.files);
      final cancellation = PasskeyCancellation();
      env.files.beforeStageFinish = () {
        env.provider.expectReleased();
        cancellation.cancel();
      };
      final error = await _failure(
        owner.auth.add(
          _passkey(PasskeyRoute.hardware, cancellation: cancellation),
        ),
        KeybayErrorCode.passkeyOperationFailed,
      );
      env.files.beforeStageFinish = null;
      expect(error.passkeyCode, PasskeyErrorCode.cancelled);
      expect(await _copyLive(env.files), before);
      expect((await owner.auth.list()).single, isA<PassphraseMethod>());
      await _expectRecords(owner);
      await _expectRecords(peer);
      env.provider.expectReleased();
    },
  );
}

final _missingId = encodeMethodId(Uint8List(16));

final class _CeremonyGate {
  final entered = Completer<void>();
  final _release = Completer<void>();

  Future<void> pause() {
    entered.complete();
    return _release.future;
  }

  void resume() {
    if (!_release.isCompleted) _release.complete();
  }
}

Future<Object?> _capture(Future<Object?> operation) async {
  try {
    return await operation;
  } on Object catch (error) {
    return error;
  }
}

PassphraseCredential _phrase() =>
    PassphraseCredential(phrase: Uint8List.fromList([1, 3, 3, 7]));

PasskeyCredential _passkey(
  PasskeyRoute route, {
  String rpId = _rpId,
  String label = 'Primary',
  String? methodId,
  PasskeyCancellation? cancellation,
}) => switch (route) {
  PasskeyRoute.system => PasskeyCredential.system(
    rpId: rpId,
    label: label,
    methodId: methodId,
    cancellation: cancellation,
  ),
  PasskeyRoute.hardware => PasskeyCredential.hardware(
    rpId: rpId,
    label: label,
    methodId: methodId,
    cancellation: cancellation,
  ),
};

final class _Environment {
  _Environment() {
    binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.passkey-engine-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('passkey-engine-test'),
      canonicalFileRoot: Uri.parse('file:///keybay-test/passkey-engine/'),
    );
    files = MemoryPinnedStoreFiles(binding);
    protector = SoftwareTestProtector(binding: binding, registry: registry);
    host = ResolvedHost(binding: binding, files: files, protector: protector);
    engine = _newEngine();
  }
  final provider = TestPasskeyProvider();
  final registry = InMemoryRootRegistry();
  final List<V2StoreSession> _sessions = [];
  late final ResolvedApplicationBinding binding;
  late final MemoryPinnedStoreFiles files;
  late final SoftwareTestProtector protector;
  late final ResolvedHost host;
  late final V2StoreEngine engine;

  V2StoreEngine _newEngine() => V2StoreEngine(
    FakeHostPlatform(host),
    passphraseDeriver: FastTestPassphraseDeriver(),
    keypassClient: provider.client,
  );

  Future<V2StoreSession> open({
    KeybayCredential? credential,
    bool freshEngine = false,
  }) async {
    final session = await (freshEngine ? _newEngine() : engine).open(
      credential: credential,
    );
    _sessions.add(session);
    return session;
  }

  Future<void> dispose() async {
    files.beforeStageFinish = null;
    for (final session in _sessions) {
      await session.close();
    }
    try {
      await engine.reset();
    } finally {
      provider.expectReleased();
      provider.clear();
      expect(files.activeHandleCount, 0);
    }
  }
}

Future<KeybayException> _failure(
  Future<Object?> operation,
  KeybayErrorCode code,
) async {
  try {
    await operation;
  } on KeybayException catch (error) {
    expect(error.code, code);
    return error;
  }
  fail('Expected KeybayException($code).');
}

Future<void> _writeRecords(KeybaySession session) async {
  await session.set('alpha', 'first');
  await session.set('middle', 'other');
  await session.set('zulu', 'final');
}

Future<void> _expectRecords(KeybaySession session) async {
  expect(await session.get('alpha'), 'first');
  expect(await session.get('middle'), 'other');
  expect(await session.get('zulu'), 'final');
}

Future<void> _expectStale(V2StoreSession peer) async {
  expect(debugStoreSessionKeyIsCleared(peer), isTrue);
  await _failure(peer.get('alpha'), KeybayErrorCode.staleSession);
}

Future<Uint8List> _copyLive(MemoryPinnedStoreFiles files) async {
  final pin = await files.openPinnedLive();
  if (pin == null) throw StateError('No live test generation.');
  try {
    return await pin.readExact(offset: 0, length: pin.length);
  } finally {
    await pin.close();
  }
}

V2Bootstrap _bootstrap(Uint8List bytes) {
  final fixed = Uint8List.sublistView(bytes, 0, v2BootstrapCoreFixedBytes);
  return decodeBootstrap(
    Uint8List.sublistView(
      bytes,
      0,
      decodeBootstrapCoreLength(fixed) + v2BootstrapLengthBytes,
    ),
  );
}

List<Uint8List> _frames(Uint8List bytes) {
  final bootstrap = _bootstrap(bytes);
  final layout = deriveStoreLayout(
    fileLength: bytes.length,
    bootstrap: bootstrap,
    sealedManifestLength: decodeManifestLength(
      Uint8List.sublistView(bytes, bytes.length - v2ManifestLengthBytes),
    ),
  );
  const length = 5 + V2StoreLimits.sealedFrameOverhead;
  expect(layout.frameRegionLength, 3 * length);
  return [
    for (var index = 0; index < 3; index++)
      Uint8List.fromList(
        Uint8List.sublistView(
          bytes,
          layout.frameRegionOffset + index * length,
          layout.frameRegionOffset + (index + 1) * length,
        ),
      ),
  ];
}

void _expectResealed(Uint8List before, Uint8List after) {
  final oldFrames = _frames(before);
  final newFrames = _frames(after);
  for (var index = 0; index < oldFrames.length; index++) {
    expect(
      newFrames[index],
      isNot(equals(oldFrames[index])),
      reason: 'Every record must change ciphertext on auth rotation.',
    );
  }
}

Future<T> _withPackage<T>(
  _Environment env,
  Future<T> Function(
    Uint8List bytes,
    V2Bootstrap bootstrap,
    PlatformRootLease lease,
    Uint8List aad,
    V2MethodsPackage package,
  )
  body,
) async {
  final bytes = await _copyLive(env.files);
  final bootstrap = _bootstrap(bytes);
  final lease = (await env.protector.openExisting(
    ProviderState(bootstrap.core.providerState),
    interaction: PlatformInteraction.forbidden,
  ))!;
  final aad = encodePlatformPackageAad(
    storageDomain: env.binding.domain.copyBytes(),
    bootstrapCore: bootstrap.core,
  );
  final offset = encodeBootstrap(bootstrap).length;
  final plaintext = await lease.openPackage(
    sealedPackage: Uint8List.sublistView(
      bytes,
      offset,
      offset + bootstrap.sealedPackageLength,
    ),
    aad: aad,
  );
  final package = decodeKeyPackage(plaintext) as V2MethodsPackage;
  try {
    return await body(bytes, bootstrap, lease, aad, package);
  } finally {
    package.clear();
    plaintext.fillRange(0, plaintext.length, 0);
    await lease.close();
  }
}

Future<int> _storedCounter(_Environment env, String id) =>
    _withPackage(env, (bytes, bootstrap, lease, aad, package) async {
      final method = package.methods.singleWhere(
        (method) => encodeMethodId(method.methodId) == id,
      );
      final json =
          jsonDecode(utf8.decode(method.passkeyRecord)) as Map<String, dynamic>;
      return json['signCount']! as int;
    });

Future<void> _forgeLabelWithPlatformRoot(_Environment env, String label) =>
    _withPackage(env, (bytes, bootstrap, lease, aad, package) async {
      final method = package.methods.single;
      final forged = V2MethodsPackage(
        storeId: package.storeId,
        epoch: package.epoch,
        methods: [
          V2AuthMethodEnvelope(
            methodId: method.methodId,
            kind: method.kind,
            label: label,
            salt: method.salt,
            profileId: method.profileId,
            publicKey: method.publicKey,
            keyEnvelope: method.keyEnvelope,
            passkeyRecord: method.passkeyRecord,
          ),
        ],
      );
      final plaintext = encodeKeyPackage(forged);
      try {
        final sealed = await lease.sealPackage(plaintext: plaintext, aad: aad);
        expect(sealed.length, bootstrap.sealedPackageLength);
        final offset = encodeBootstrap(bootstrap).length;
        bytes.setRange(offset, offset + sealed.length, sealed);
        env.files.replaceLiveBytes(bytes);
      } finally {
        plaintext.fillRange(0, plaintext.length, 0);
        forged.clear();
      }
    });
