@TestOn('mac-os || linux')
@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:keybay/keybay.dart';
import 'package:test/test.dart';

import 'support/v2_store_crash_worker.dart';

void main() {
  for (final operation in ['write', 'rotate']) {
    for (final point in [
      'partial-stage',
      'before-replace',
      'after-replace',
      'acknowledged',
    ]) {
      test(
        '$operation survives SIGKILL at $point with one complete generation',
        () async {
          final created = Directory.systemTemp.createTempSync('keybay-crash-');
          final root = Directory(created.resolveSymbolicLinksSync());
          Process? worker;
          addTearDown(() async {
            worker?.kill(ProcessSignal.sigkill);
            await worker?.exitCode;
            if (root.existsSync()) root.deleteSync(recursive: true);
          });
          for (final dir in [
            root,
            Directory('${root.path}/store'),
            Directory('${root.path}/provider'),
          ]) {
            dir.createSync(recursive: true);
            expect(Process.runSync('chmod', ['700', dir.path]).exitCode, 0);
          }
          final engine = CrashHost(root).engine();
          final initial = await engine.open();
          expect(initial.wasInitialized, isTrue);
          await initial.set('stable', 'acknowledged-value-canary');
          await initial.set('value', 'old-value-canary');
          await initial.auth.add(crashPhrase('original'));
          await initial.close();
          final originalStore = File(
            '${root.path}/store/keybay.v2.store',
          ).readAsBytesSync();
          final package = await Isolate.resolvePackageUri(
            Uri.parse('package:keybay/keybay.dart'),
          );
          final packageRoot = File.fromUri(package!).parent.parent;
          worker = await Process.start(Platform.resolvedExecutable, [
            '${packageRoot.path}/test/support/v2_store_crash_worker.dart',
            root.path,
            operation,
            point,
          ], workingDirectory: packageRoot.path);
          final output = worker.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter());
          final errors = worker.stderr.transform(utf8.decoder).join();
          try {
            expect(
              await output.first.timeout(const Duration(seconds: 20)),
              'ready:$point',
            );
          } on Object {
            worker.kill(ProcessSignal.sigkill);
            final code = await worker.exitCode.timeout(
              const Duration(seconds: 10),
            );
            fail(
              'worker did not reach $point: exit=$code stderr=${await errors}',
            );
          }
          expect(worker.kill(ProcessSignal.sigkill), isTrue);
          expect(
            await worker.exitCode.timeout(const Duration(seconds: 10)),
            -9,
          );
          expect(await errors, isEmpty);

          final replaced = point == 'after-replace' || point == 'acknowledged';
          final recoveredEngine = CrashHost(root).engine();
          final currentPhrase = operation == 'rotate' && replaced
              ? 'replacement'
              : 'original';
          if (operation == 'rotate') {
            final wrongPhrase = replaced ? 'original' : 'replacement';
            await expectLater(
              recoveredEngine.open(credential: crashPhrase(wrongPhrase)),
              throwsA(
                isA<KeybayException>().having(
                  (e) => e.code,
                  'code',
                  KeybayErrorCode.unlockFailed,
                ),
              ),
            );
          }
          final recovered = await recoveredEngine.open(
            credential: crashPhrase(currentPhrase),
          );
          expect(recovered.wasInitialized, isFalse);
          expect(await recovered.get('stable'), 'acknowledged-value-canary');
          expect(
            await recovered.get('value'),
            operation == 'write' && replaced
                ? 'new-value-canary'
                : 'old-value-canary',
          );
          expect(await recovered.listKeys(), ['stable', 'value']);
          final live = File(
            '${root.path}/store/keybay.v2.store',
          ).readAsBytesSync();
          expect(latin1.decode(live), isNot(contains('value-canary')));
          if (!replaced) expect(live, originalStore);
          expect(
            File('${root.path}/store/keybay.v2.stage').existsSync(),
            isFalse,
          );
          // A successful subsequent mutation proves the dead process released its
          // native lock and abandoned ciphertext cannot obstruct the next writer.
          await recovered.set('after-crash', 'writable');
          await recovered.close();
          await recoveredEngine.reset();
        },
      );
    }
  }
}
