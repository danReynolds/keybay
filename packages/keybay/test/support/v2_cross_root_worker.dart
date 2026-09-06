import 'dart:async';
import 'dart:io';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/platform_protector.dart';

import 'v2_disposable_file_protector.dart';

const String _applicationId = 'dev.keybay.cross-root-test';
const String _profileCode = 'test.file-provider';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 4) {
    exitCode = disposableWorkerFailureExitCode;
    return;
  }

  PlatformRootLease? lease;
  try {
    final providerDirectory = Directory(arguments[0]);
    final candidateRoot = Directory(arguments[1]);
    final canonicalRoot = candidateRoot.resolveSymbolicLinksSync();
    final binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: _applicationId,
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile(_profileCode),
      canonicalFileRoot: Uri.directory(canonicalRoot),
    );
    final protector = DisposableFileProtector(
      binding: binding,
      providerDirectory: providerDirectory,
      creationDelay: const Duration(milliseconds: 300),
    );

    File(arguments[2]).writeAsStringSync('ready');
    await _waitForGo(File(arguments[3]));

    final creation = await protector.createOnly(
      interaction: PlatformInteraction.forbidden,
    );
    lease = creation.lease;
    if (creation.disposition != RootCreationDisposition.created) {
      throw StateError('unexpected creation disposition');
    }
    final sealed = await lease.sealPackage(
      plaintext: disposableProofPlaintext(),
      aad: disposableProofAad(binding),
    );
    final proof = DisposableStoreProof(
      providerState: lease.providerState,
      sealedPackage: sealed,
    );
    writeDisposableStoreProof(
      '${candidateRoot.path}/$disposableProofFileName',
      proof,
    );
  } on PlatformProtectorFailure catch (failure) {
    if (failure.code == PlatformProtectorFailureCode.stateConflict) {
      exitCode = disposableStateConflictExitCode;
      return;
    }
    stderr.writeln('worker protector failure: ${failure.code.name}');
    exitCode = disposableWorkerFailureExitCode;
  } catch (error) {
    stderr.writeln('worker failure: ${error.runtimeType}');
    exitCode = disposableWorkerFailureExitCode;
  } finally {
    await lease?.close();
  }
}

Future<void> _waitForGo(File marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!marker.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('cross-root worker barrier timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
