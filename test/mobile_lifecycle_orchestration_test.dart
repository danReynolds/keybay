import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'native lifecycle runners preserve upgrade state and failed outcomes',
    () {
      final result = Process.runSync('python3', [
        '-B',
        'test/support/mobile_lifecycle_tools_test.py',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
  );
}
