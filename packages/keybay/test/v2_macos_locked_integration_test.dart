@Tags(['integration'])
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  final helper = Platform.environment['KEYBAY_TEST_KEYCHAIN_HELPER'];
  final accountHome = Platform.environment['KEYBAY_TEST_KEYCHAIN_HOME'];
  test(
    'locked classic Keychain cannot prompt record operations',
    () async {
      final files = Directory.systemTemp.createTempSync(
        'keybay_locked_records_',
      );
      final packageConfig = await Isolate.packageConfig;
      final worker = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/keybay.dart'),
      );
      final entrypoint = worker!.resolve(
        '../test/support/macos_locked_store_worker.dart',
      );
      Process? process;
      try {
        process = await Process.start(Platform.resolvedExecutable, [
          '--packages=${File.fromUri(packageConfig!).path}',
          File.fromUri(entrypoint).path,
          files.resolveSymbolicLinksSync(),
        ]);
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.transform(utf8.decoder).join();
        int exitCode;
        try {
          exitCode = await process.exitCode.timeout(
            const Duration(seconds: 30),
          );
        } on Object {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
          throw StateError('Locked-store worker timed out: ${await stderr}');
        }
        final output = await stdout;
        final diagnostics = await stderr;
        expect(exitCode, 0, reason: '$output\n$diagnostics');
        expect(output, 'locked-records-ok\n');
      } finally {
        process?.kill();
        // The worker closes its sessions. The shell adapter deletes the
        // disposable Keychain while locked; this parent owns its store files.
        files.deleteSync(recursive: true);
      }
    },
    // The worker owns the operation deadline and must finish cleanup before
    // the test runner cancels this enclosing test.
    timeout: const Timeout(Duration(seconds: 45)),
    skip:
        Platform.environment['KEYBAY_INTEGRATION'] != '1' ||
            helper == null ||
            accountHome == null
        ? 'run tool/test_macos_native.sh with its disposable Keychain'
        : false,
  );
}
