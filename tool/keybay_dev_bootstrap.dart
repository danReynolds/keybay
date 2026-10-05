// Source development runner. Prepare hooks in the repository first, then keep
// the original CLI entrypoint, caller directory, stdin and process exit status.
import 'dart:io';
import 'dart:isolate';

Future<void> main(List<String> arguments) async {
  final entrypoint = Platform.script.resolve(
    '../packages/keybay_cli/bin/keybay.dart',
  );
  final packages = await Isolate.packageConfig;
  Directory.current = arguments.first;
  final events = ReceivePort();
  try {
    await Isolate.spawnUri(
      entrypoint,
      arguments.sublist(1),
      null,
      packageConfig: packages,
      onExit: events.sendPort,
      onError: events.sendPort,
      errorsAreFatal: true,
    );
    await for (final event in events) {
      if (event == null) break;
      stderr.writeln((event as List).join('\n'));
      exitCode = 255;
    }
  } finally {
    events.close();
  }
}
