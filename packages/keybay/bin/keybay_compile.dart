import 'dart:io';
import 'dart:isolate';

import 'package:keybay/src/v2/application_identity.dart';

const int _usageExitCode = 64;

Future<void> main(List<String> arguments) async {
  final separateModule =
      arguments.isNotEmpty && arguments.first == '--aot-snapshot';
  if (separateModule) arguments = arguments.sublist(1);
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
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'compile',
        separateModule ? 'aot-snapshot' : 'exe',
        '-Dkeybay.application_id=${identity.stableValue}',
        if (packageConfig != null)
          '--packages=${File.fromUri(packageConfig).path}',
        '-o',
        output,
        canonicalEntrypoint.path,
      ],
      workingDirectory: canonicalEntrypoint.parent.path,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
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
    'Usage: dart run keybay:keybay_compile [--aot-snapshot] <entrypoint.dart> -o <output>',
  );
}
