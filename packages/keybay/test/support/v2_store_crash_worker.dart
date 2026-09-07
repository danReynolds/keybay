// Test-only process fixture: production engine/POSIX files, disposable provider
// and fast deterministic KDF. No platform custody or power-loss claim.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart' show V2StoreEngine;
import 'package:keybay/src/v2/posix_store_files.dart';
import 'package:keybay/src/v2/store_files.dart';

import 'v2_disposable_file_protector.dart';
import 'v2_test_keybay.dart' show FastTestPassphraseDeriver;

PassphraseCredential crashPhrase(String value) =>
    PassphraseCredential(phrase: Uint8List.fromList(utf8.encode(value)));

final class CrashHost implements HostPlatform {
  CrashHost(Directory root, {String? pauseAt}) {
    final storeRoot = Directory('${root.path}/store');
    binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.crash-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('test.crash'),
      canonicalFileRoot: storeRoot.uri,
    );
    _files = _CrashFiles(
      PosixStoreFiles(binding: binding, canonicalFileRoot: storeRoot.uri),
      pauseAt,
    );
    host = ResolvedHost(
      binding: binding,
      files: _files,
      protector: DisposableFileProtector(
        binding: binding,
        providerDirectory: Directory('${root.path}/provider'),
      ),
    );
  }

  late final ResolvedApplicationBinding binding;
  late final _CrashFiles _files;
  late final ResolvedHost host;
  V2StoreEngine engine() =>
      V2StoreEngine(this, passphraseDeriver: FastTestPassphraseDeriver());
  void arm() => _files.armed = true;
  Future<void> checkpoint(String point) => _files.checkpoint(point);
  @override
  Future<ResolvedHost> resolve() async => host;
}

final class _CrashFiles implements StoreFiles {
  _CrashFiles(this.inner, this.pauseAt);
  final StoreFiles inner;
  final String? pauseAt;
  bool armed = false;

  Future<void> checkpoint(String point) async {
    if (!armed || point != pauseAt) return;
    final keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {});
    try {
      stdout.writeln('ready:$point');
      await stdout.flush();
      await Completer<void>().future;
    } finally {
      keepAlive.cancel();
    }
  }

  @override
  ResolvedApplicationBinding get binding => inner.binding;
  @override
  Future<PinnedStoreFile?> openPinnedLive() => inner.openPinnedLive();
  @override
  Future<T> withExclusiveTransaction<T>(
    Future<T> Function(StoreTransaction) operation,
  ) => inner.withExclusiveTransaction(
    (tx) => operation(_CrashTransaction(tx, this)),
  );
}

final class _CrashTransaction implements StoreTransaction {
  _CrashTransaction(this.inner, this.files);
  final StoreTransaction inner;
  final _CrashFiles files;
  @override
  Future<StoreArtifacts> observeArtifacts() => inner.observeArtifacts();
  @override
  Future<PinnedStoreFile?> openPinnedLive() => inner.openPinnedLive();
  @override
  Future<void> discardAbandonedStaging() => inner.discardAbandonedStaging();
  @override
  Future<void> resetManagedArtifacts() => inner.resetManagedArtifacts();
  @override
  Future<StagedStoreFile> createStaging({required int expectedLength}) async =>
      _CrashStage(
        await inner.createStaging(expectedLength: expectedLength),
        files,
      );
}

final class _CrashStage implements StagedStoreFile {
  _CrashStage(this.inner, this.files);
  final StagedStoreFile inner;
  final _CrashFiles files;
  @override
  Future<void> append(Uint8List bytes) async {
    await inner.append(bytes);
    await files.checkpoint('partial-stage');
  }

  @override
  Future<PinnedStoreFile> finish() => inner.finish();
  @override
  Future<void> replaceLive() async {
    await files.checkpoint('before-replace');
    await inner.replaceLive();
    await files.checkpoint('after-replace');
  }
}

Future<void> main(List<String> args) async {
  try {
    final host = CrashHost(Directory(args[0]), pauseAt: args[2]);
    final engine = host.engine();
    final session = await engine.open(credential: crashPhrase('original'));
    if (session.wasInitialized) throw StateError('worker initialized');
    host.arm();
    if (args[1] == 'write') {
      await session.set('value', 'new-value-canary');
    } else if (args[1] == 'rotate') {
      await session.auth.update(crashPhrase('replacement'));
    } else {
      throw StateError('unknown operation');
    }
    await host.checkpoint('acknowledged');
    throw StateError('worker missed its crash boundary');
  } on Object catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(70);
  }
}
