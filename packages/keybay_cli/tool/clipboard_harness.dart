// Disposable native clipboard qualification. Never touches macOS general board.
import 'dart:io';
import 'package:keybay_cli/src/tui/clipboard.dart';

const sample = '{\\rtf1 this is plain text}\r\n🔑 café\n';

Future<void> main(List<String> args) async {
  if (Platform.isMacOS) {
    if (args.length != 1 || !args.single.startsWith('dev.keybay.test.')) {
      exit(2);
    }
    MacPasteboard().write(sample, boardName: args.single);
  } else {
    final copy = systemCopy();
    if (copy == null) exit(69);
    await copy(sample);
  }
}
