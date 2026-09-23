@Tags(['unit'])
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:keybay_cli/src/process_hardening.dart';
import 'package:test/test.dart';

void main() {
  test('commands disable core files and restore them only for exec', () {
    final caller = ProcessHardening.softCoreLimit;
    expect(caller, isNotNull);

    ProcessHardening.apply();
    expect(ProcessHardening.softCoreLimit, 0);
    if (Platform.isLinux) expect(ProcessHardening.dumpable, 0);

    ProcessHardening.restoreForExec();
    expect(ProcessHardening.softCoreLimit, caller);

    ProcessHardening.reapplyAfterFailedExec();
    expect(ProcessHardening.softCoreLimit, 0);
  });
}
