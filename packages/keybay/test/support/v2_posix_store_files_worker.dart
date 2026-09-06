import 'dart:async';
import 'dart:io';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/posix_store_files.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    exitCode = 2;
    return;
  }
  try {
    final root = Directory(arguments[0]);
    final canonicalRoot = Uri.directory(root.absolute.path);
    final binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.posix-store-files-test',
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('test.posix-store-files'),
      canonicalFileRoot: canonicalRoot,
    );
    final files = PosixStoreFiles(
      binding: binding,
      canonicalFileRoot: canonicalRoot,
    );
    await files.withExclusiveTransaction((_) async {
      File(arguments[1]).writeAsStringSync('ready');
      await _waitFor(File(arguments[2]));
    });
  } on Object catch (error) {
    stderr.writeln('POSIX store worker failed: ${error.runtimeType}');
    exitCode = 1;
  }
}

Future<void> _waitFor(File marker) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!marker.existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('POSIX store worker release timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
