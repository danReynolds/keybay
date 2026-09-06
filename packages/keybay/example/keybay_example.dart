// A tiny CLI demonstrating the core public API.
//
//   dart run example/keybay_example.dart
import 'dart:io';

import 'package:keybay/keybay.dart';

Future<void> main() async {
  final session = await Keybay.open();
  try {
    await session.set('demo/api-token', 's3cr3t-value');
    stdout.writeln('read back: ${await session.get('demo/api-token')}');
    stdout.writeln('present:   ${await session.contains('demo/api-token')}');
    await session.delete('demo/api-token');
  } finally {
    await session.close();
  }
}
