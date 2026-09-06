import 'dart:io';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/entrypoint.dart';

Future<void> main(List<String> arguments) async {
  if (arguments case <String>['--test-reset']) {
    await Keybay.reset();
    return;
  }
  final status = await runKeybay(arguments);
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
