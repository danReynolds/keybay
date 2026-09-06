import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:keybay/src/v2/posix_store_files.dart';
import 'package:keybay/src/v2/store_files.dart';

final int Function(int) _umask = DynamicLibrary.process()
    .lookupFunction<Uint32 Function(Uint32), int Function(int)>('umask');

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 2;
    return;
  }
  try {
    _umask(0x1ff);
    final root = Directory(arguments.single);
    final canonicalRoot = Uri.directory(root.absolute.path);
    final binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: 'dev.keybay.posix-store-files-umask-test',
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
    await files.withExclusiveTransaction((transaction) async {
      final stage = await transaction.createStaging(expectedLength: 1);
      await stage.append(Uint8List.fromList(<int>[7]));
      final pin = await stage.finish();
      await pin.close();
      await stage.replaceLive();
    });
  } on StoreFilesFailure catch (error) {
    stderr.writeln('POSIX hostile-umask worker failed: ${error.code.name}');
    exitCode = 3;
  } on Object catch (error) {
    stderr.writeln('POSIX hostile-umask worker failed: ${error.runtimeType}');
    exitCode = 1;
  }
}
