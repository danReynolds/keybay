@TestOn('mac-os || linux')
@Tags(['unit'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';
import 'package:test/test.dart';

import 'support/v2_disposable_file_protector.dart';

void main() {
  test(
    'different roots race for one provider identity without split initialization',
    () async {
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_cross_root_',
      );
      final processes = <Process>[];
      addTearDown(() async {
        for (final process in processes) {
          process.kill();
        }
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      final chmod = Process.runSync('chmod', <String>['700', fixture.path]);
      if (chmod.exitCode != 0) {
        fail('could not make the disposable fixture private');
      }
      final providerDirectory = Directory('${fixture.path}/provider');
      final rootA = Directory('${fixture.path}/root-a');
      final rootB = Directory('${fixture.path}/root-b');
      final barrierDirectory = Directory('${fixture.path}/barrier');
      for (final directory in <Directory>[
        providerDirectory,
        rootA,
        rootB,
        barrierDirectory,
      ]) {
        directory.createSync(recursive: true);
        final chmod = Process.runSync('chmod', <String>['700', directory.path]);
        if (chmod.exitCode != 0) {
          fail('could not make a disposable directory private');
        }
      }

      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/keybay.dart'),
      );
      if (packageLibrary == null) fail('could not resolve the keybay package');
      final packageRoot = File.fromUri(packageLibrary).parent.parent;
      final worker = File(
        '${packageRoot.path}/test/support/v2_cross_root_worker.dart',
      );
      expect(worker.existsSync(), isTrue);

      final go = File('${barrierDirectory.path}/go');
      final readyA = File('${barrierDirectory.path}/ready-a');
      final readyB = File('${barrierDirectory.path}/ready-b');

      Future<_WorkerProcess> startWorker(
        Directory candidateRoot,
        File ready,
      ) async {
        final process = await Process.start(
          Platform.resolvedExecutable,
          <String>[
            worker.path,
            providerDirectory.path,
            candidateRoot.path,
            ready.path,
            go.path,
          ],
          workingDirectory: packageRoot.path,
        );
        processes.add(process);
        return _WorkerProcess(
          process: process,
          stdout: process.stdout.transform(utf8.decoder).join(),
          stderr: process.stderr.transform(utf8.decoder).join(),
        );
      }

      final workerA = await startWorker(rootA, readyA);
      final workerB = await startWorker(rootB, readyB);
      await _waitForReady(<File>[readyA, readyB]);
      go.writeAsStringSync('go');

      final exitCodes = <int>[
        await workerA.process.exitCode,
        await workerB.process.exitCode,
      ]..sort();
      final standardOutput = await Future.wait<String>(<Future<String>>[
        workerA.stdout,
        workerB.stdout,
      ]);
      final standardError = await Future.wait<String>(<Future<String>>[
        workerA.stderr,
        workerB.stderr,
      ]);
      expect(exitCodes, <int>[
        0,
        disposableStateConflictExitCode,
      ], reason: 'stdout=$standardOutput stderr=$standardError');

      final proofA = File('${rootA.path}/$disposableProofFileName');
      final proofB = File('${rootB.path}/$disposableProofFileName');
      expect(
        <bool>[
          proofA.existsSync(),
          proofB.existsSync(),
        ].where((exists) => exists).length,
        1,
        reason: 'only the provider-binding winner may initialize its root',
      );
      final providerRecords = providerDirectory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.provider'))
          .toList();
      expect(providerRecords, hasLength(1));

      final winningRoot = proofA.existsSync() ? rootA : rootB;
      final losingRoot = identical(winningRoot, rootA) ? rootB : rootA;
      final winningBinding = _bindingFor(winningRoot);
      final losingBinding = _bindingFor(losingRoot);
      expect(winningBinding.providerAddress, losingBinding.providerAddress);
      expect(winningBinding.domain, isNot(losingBinding.domain));

      final proof = readDisposableStoreProof(
        '${winningRoot.path}/$disposableProofFileName',
      );
      final winner = DisposableFileProtector(
        binding: winningBinding,
        providerDirectory: providerDirectory,
      );
      final lease = await winner.openExisting(
        proof.providerState,
        interaction: PlatformInteraction.forbidden,
      );
      expect(lease, isNotNull);
      expect(
        await lease!.openPackage(
          sealedPackage: proof.copySealedPackage(),
          aad: disposableProofAad(winningBinding),
        ),
        disposableProofPlaintext(),
      );
      await lease.close();

      final loser = DisposableFileProtector(
        binding: losingBinding,
        providerDirectory: providerDirectory,
      );
      await expectLater(
        loser.createOnly(interaction: PlatformInteraction.forbidden),
        throwsA(
          isA<PlatformProtectorFailure>().having(
            (failure) => failure.code,
            'code',
            PlatformProtectorFailureCode.stateConflict,
          ),
        ),
      );
      expect(
        File('${losingRoot.path}/$disposableProofFileName').existsSync(),
        isFalse,
      );
      final reset = await winner.prepareReset(
        interaction: PlatformInteraction.forbidden,
      );
      try {
        File('${winningRoot.path}/$disposableProofFileName').deleteSync();
        await reset.commit();
        expect(providerRecords.single.existsSync(), isFalse);
      } finally {
        await reset.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

ResolvedApplicationBinding _bindingFor(Directory candidateRoot) =>
    ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.cross-root-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('test.file-provider'),
      canonicalFileRoot: Uri.directory(
        candidateRoot.resolveSymbolicLinksSync(),
      ),
    );

Future<void> _waitForReady(List<File> markers) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!markers.every((marker) => marker.existsSync())) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('cross-root workers did not reach the barrier');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _WorkerProcess {
  const _WorkerProcess({
    required this.process,
    required this.stdout,
    required this.stderr,
  });

  final Process process;
  final Future<String> stdout;
  final Future<String> stderr;
}
