import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String gate;

  setUpAll(() async {
    final workflow = await File('.github/workflows/ci.yml').readAsString();
    gate = _job(workflow, 'provider-gate', 'site');
  });

  test('provider gate always materializes outside the scheduled fuzz lane', () {
    expect(
      gate,
      contains(r"if: ${{ always() && github.event_name != 'schedule' }}"),
    );
    for (final dependency in <String>[
      'provider-impact',
      'integration-macos',
      'integration-linux',
      'integration-flatpak',
      'integration-android',
      'integration-ios',
    ]) {
      expect(gate, contains('      - $dependency'));
    }
  });

  test('provider gate binds every selection to its job result', () {
    for (final provider in <String>['MACOS', 'LINUX', 'ANDROID', 'IOS']) {
      expect(gate, contains('      ${provider}_REQUIRED:'));
      expect(gate, contains('      ${provider}_RESULT:'));
    }
    expect(gate, contains('true:success|false:skipped'));
    expect(gate, contains('provider-impact did not succeed'));
    expect(
      gate,
      contains(r'check_provider flatpak "$LINUX_REQUIRED" "$FLATPAK_RESULT"'),
    );
  });
}

String _job(String workflow, String name, String next) {
  final start = workflow.indexOf('  $name:');
  final end = workflow.indexOf('\n  $next:', start);
  if (start < 0 || end < 0) throw StateError('workflow job not found: $name');
  return workflow.substring(start, end);
}
