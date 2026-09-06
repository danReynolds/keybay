@TestOn('mac-os || linux')
@Tags(['unit'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/v2/keybay_v2.dart';
import 'package:test/test.dart';

import 'support/v2_store_crash_worker.dart';
import 'support/v2_test_keybay.dart' show FastTestPassphraseDeriver;

// Real engine and POSIX locks; disposable provider and fast test KDF. Unlike
// the memory fake's immediate busy result, a native contender waits for release.
void main() {
  for (final failRotation in [false, true]) {
    test(
      'waiting writer respects ${failRotation ? 'aborted' : 'committed'} auth rotation',
      () async {
        final root = Directory(
          Directory.systemTemp
              .createTempSync('keybay-rotation-contention-')
              .resolveSymbolicLinksSync(),
        );
        addTearDown(() => root.deleteSync(recursive: true));
        for (final name in ['store', 'provider']) {
          final directory = Directory('${root.path}/$name')..createSync();
          expect(Process.runSync('chmod', ['700', directory.path]).exitCode, 0);
        }
        final deriver = _PausedDeriver(failRotation: failRotation);
        final engine = V2StoreEngine(
          CrashHost(root),
          passphraseDeriver: deriver,
        );
        final owner = await engine.open();
        addTearDown(owner.close);
        final peer = await engine.open();
        addTearDown(peer.close);
        // Unblock accepted work even if an assertion fails before release.
        addTearDown(deriver.release);
        await owner.set('stable', 'acknowledged');

        final rotation = owner.auth.add(crashPhrase('replacement'));
        final rotationResult = failRotation
            ? expectLater(
                rotation,
                throwsA(_failure(KeybayErrorCode.storageOperationFailed)),
              )
            : expectLater(rotation, completes);
        await deriver.entered.future;

        var writerFinished = false;
        final writing = peer
            .set('contender', 'accepted-after-abort')
            .whenComplete(() => writerFinished = true);
        final writerResult = expectLater(
          writing,
          failRotation
              ? completes
              : throwsA(_failure(KeybayErrorCode.staleSession)),
        );
        // Drain the operation queue so the contender reaches the native lock
        // while rotation is paused, without a timing-dependent sleep.
        await Future<void>.delayed(Duration.zero);
        expect(writerFinished, isFalse);
        deriver.release();
        await Future.wait([rotationResult, writerResult]);

        expect(debugStoreSessionKeyIsCleared(peer), !failRotation);
        expect(await owner.get('stable'), 'acknowledged');
        expect(
          await owner.get('contender'),
          failRotation ? 'accepted-after-abort' : isNull,
        );
        final recovered = await engine.open(
          credential: failRotation ? null : crashPhrase('replacement'),
        );
        addTearDown(recovered.close);
        expect(recovered.wasInitialized, isFalse);
        expect(await recovered.auth.list(), hasLength(failRotation ? 0 : 1));
        expect(await recovered.get('stable'), 'acknowledged');
        await recovered.set('after', 'still-writable');
        await engine.reset();
        expect(
          File('${root.path}/store/keybay.v2.store').existsSync(),
          isFalse,
        );
        expect(
          File('${root.path}/store/keybay.v2.stage').existsSync(),
          isFalse,
        );
      },
    );
  }
}

final class _PausedDeriver implements V2PassphraseDeriver {
  _PausedDeriver({required this.failRotation});
  final bool failRotation;
  final entered = Completer<void>();
  final _release = Completer<void>();
  final _inner = FastTestPassphraseDeriver();

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) {
    // Snapshot/derive before returning; the engine immediately clears its input.
    final deriving = _inner.derive(
      passphrase: passphrase,
      profileId: profileId,
      salt: salt,
    );
    if (entered.isCompleted) return deriving;
    entered.complete();
    return deriving.then((key) async {
      await _release.future;
      if (failRotation) {
        key.fillRange(0, key.length, 0);
        throw const V2PassphraseDerivationFailure(
          V2PassphraseDerivationFailureCode.operationFailed,
        );
      }
      return key;
    });
  }
}

Matcher _failure(KeybayErrorCode code) =>
    isA<KeybayException>().having((error) => error.code, 'code', code);
