import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('iOS CI uses the bounded in-process XCTest result bridge', () {
    final script = File('tool/test_mobile_ci.sh').readAsStringSync();
    final iosLeg = script.split('  ios)').last.split('  *)').first;

    expect(
      iosLeg,
      contains('flutter build ios --config-only --simulator --debug'),
    );
    expect(iosLeg, contains('xcodebuild test'));
    expect(iosLeg, contains('-parallel-testing-enabled NO'));
    expect(iosLeg, contains(r'-resultBundlePath "$result_bundle"'));
    expect(iosLeg, contains(r'tail -n 500 "$xcode_log"'));
    expect(
      iosLeg,
      isNot(contains('flutter test integration_test/keybay_v2_ios_test.dart')),
      reason: 'Flutter VM-service log discovery can wait indefinitely',
    );

    final nativeRunner = File(
      'example_flutter/ios/RunnerTests/RunnerTests.m',
    ).readAsStringSync();
    expect(nativeRunner, contains('dateWithTimeIntervalSinceNow:120'));
    expect(nativeRunner, contains('@"testResults"'));

    final dartSuite = File(
      'example_flutter/integration_test/keybay_v2_ios_test.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'^\s*test\(', multiLine: true).hasMatch(dartSuite),
      isFalse,
      reason: 'plain test() cases bypass IntegrationTestPlugin result capture',
    );
    final support = File(
      'example_flutter/integration_test/mobile_security_support.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'^\s*test\(', multiLine: true).hasMatch(support),
      isFalse,
      reason: 'receipt metadata must also reach the in-process result bridge',
    );
  });
}
