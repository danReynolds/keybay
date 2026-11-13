import 'dart:io';
import 'dart:isolate';

import 'package:keybay/src/v2/application_identity.dart';

const int _usageExitCode = 64;

Future<void> main(List<String> arguments) async {
  var separateModule = false;
  var processHardening = true;
  while (arguments.isNotEmpty && arguments.first.startsWith('--')) {
    if (arguments.first == '--aot-snapshot' && !separateModule) {
      separateModule = true;
    } else if (arguments.first == '--no-process-hardening' &&
        processHardening) {
      processHardening = false;
    } else {
      break;
    }
    arguments = arguments.sublist(1);
  }
  if (arguments.length != 3 ||
      (arguments[1] != '-o' && arguments[1] != '--output') ||
      arguments[0].isEmpty ||
      arguments[2].isEmpty) {
    _printUsage();
    exitCode = _usageExitCode;
    return;
  }

  final entrypoint = File(arguments[0]);
  if (!entrypoint.path.endsWith('.dart')) {
    _printUsage();
    exitCode = _usageExitCode;
    return;
  }

  try {
    final canonicalEntrypoint = File(entrypoint.resolveSymbolicLinksSync());
    final identity = DartApplicationIdentityResolver(
      DartRuntimeIdentityInputs(
        script: canonicalEntrypoint.uri,
        packageConfig: null,
        resolvedExecutable: Uri.file(Platform.resolvedExecutable),
        embeddedApplicationId: '',
      ),
    ).resolve();
    final output = File(arguments[2]).absolute.path;
    final packageConfig = await Isolate.packageConfig;
    final stage = await Directory.systemTemp.createTemp('keybay-compile-');
    try {
      final kernel = '${stage.path}/application.dill';
      // This custom packager owns the sibling-library bundle. Resolve the
      // application and its embedded identity into kernel first, then compile
      // that kernel without asking Dart to run the automatic build hooks.
      // Ordinary consumers continue to use `dart run` or `dart build cli`.
      final prepare = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          'compile',
          'kernel',
          '-Dkeybay.application_id=${identity.stableValue}',
          '-Dkeypass.hardware.manual_bundle=true',
          // The output is a product AOT build. Say so here, so Keybay's
          // release detection never depends on when constants are folded.
          '-Ddart.vm.product=true',
          if (!processHardening) '-Dkeybay.process_hardening=false',
          if (packageConfig != null)
            '--packages=${File.fromUri(packageConfig).path}',
          '-o',
          kernel,
          canonicalEntrypoint.path,
        ],
        workingDirectory: canonicalEntrypoint.parent.path,
        mode: ProcessStartMode.inheritStdio,
      );
      exitCode = await prepare.exitCode;
      if (exitCode != 0) return;
      final compile = await Process.start(
        Platform.resolvedExecutable,
        [
          'compile',
          separateModule ? 'aot-snapshot' : 'exe',
          '-o',
          output,
          kernel,
        ],
        workingDirectory: stage.path,
        mode: ProcessStartMode.inheritStdio,
      );
      exitCode = await compile.exitCode;
    } finally {
      await stage.delete(recursive: true);
    }
  } on ApplicationIdentityFailure catch (error) {
    stderr.writeln(
      'Keybay could not embed an application identity (${error.code.name}).',
    );
    stderr.writeln(
      'Add an unquoted keybay.application_id declaration to the entrypoint\'s '
      'owning pubspec.yaml.',
    );
    exitCode = _usageExitCode;
  } on FileSystemException {
    stderr.writeln('Keybay could not read the Dart entrypoint.');
    exitCode = _usageExitCode;
  } on ProcessException {
    stderr.writeln('Keybay could not start the Dart compiler.');
    exitCode = _usageExitCode;
  }
}

void _printUsage() {
  stderr.writeln(
    'Usage: dart run keybay:keybay_compile [--aot-snapshot] '
    '[--no-process-hardening] <entrypoint.dart> -o <output>',
  );
  stderr.writeln(
    '--no-process-hardening builds with keybay.process_hardening=false, which '
    'weakens protection: see doc/sdk.md#process-hardening.',
  );
}
