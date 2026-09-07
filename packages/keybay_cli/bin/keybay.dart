import 'dart:io';

import 'package:keybay_cli/src/entrypoint.dart';

Future<void> main(List<String> arguments) async {
  final status = await runKeybay(arguments);
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
