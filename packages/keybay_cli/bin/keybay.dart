import 'dart:io';

import 'package:keybay_cli/src/entrypoint.dart';
import 'package:keybay_cli/src/tui/hardware_connection.dart';
import 'package:keybay_cli/src/unlock_preference_file.dart';

Future<void> main(List<String> arguments) async {
  final status = await runKeybay(
    arguments,
    unlockPreference: FileUnlockPreference.forCurrentUser(),
    hardwareConnected: hardwareConnected,
  );
  await stdout.flush();
  await stderr.flush();
  exit(status);
}
