import 'package:test/test.dart';

import '../tool/ci_provider_impact.dart';

void main() {
  test('documentation-only changes do not spend provider runners', () {
    final impact = classifyProviderImpact(['README.md', 'doc/design.md']);
    expect(impact.macos, isFalse);
    expect(impact.linux, isFalse);
    expect(impact.android, isFalse);
    expect(impact.ios, isFalse);
  });

  test('core implementation changes exercise every supported provider', () {
    final impact =
        classifyProviderImpact(['packages/keybay/lib/src/secret_storage.dart']);
    expect(impact.macos, isTrue);
    expect(impact.linux, isTrue);
    expect(impact.android, isTrue);
    expect(impact.ios, isTrue);
  });

  test('CLI changes exercise only its two supported desktop providers', () {
    final impact = classifyProviderImpact([
      'packages/keybay_cli/lib/src/command.dart',
    ]);
    expect(impact.macos, isTrue);
    expect(impact.linux, isTrue);
    expect(impact.android, isFalse);
    expect(impact.ios, isFalse);
  });

  test('mobile harness changes exercise both mobile providers', () {
    final impact = classifyProviderImpact([
      'example_flutter/integration_test/keybay_test.dart',
    ]);
    expect(impact.macos, isFalse);
    expect(impact.linux, isFalse);
    expect(impact.android, isTrue);
    expect(impact.ios, isTrue);
  });

  test('core version changes exercise every supported provider', () {
    final impact = classifyProviderImpact(const [], coreVersionChanged: true);
    expect(impact.macos, isTrue);
    expect(impact.linux, isTrue);
    expect(impact.android, isTrue);
    expect(impact.ios, isTrue);
  });

  test('CLI version changes exercise its release providers', () {
    final impact = classifyProviderImpact(
      const [],
      cliVersionChanged: true,
    );
    expect(impact.macos, isTrue);
    expect(impact.linux, isTrue);
    expect(impact.android, isFalse);
    expect(impact.ios, isFalse);
  });

  test('workflow and manual runs exercise every provider', () {
    for (final impact in [
      classifyProviderImpact(['.github/workflows/ci.yml']),
      classifyProviderImpact(const [], forceAll: true),
    ]) {
      expect(impact.macos, isTrue);
      expect(impact.linux, isTrue);
      expect(impact.android, isTrue);
      expect(impact.ios, isTrue);
    }
  });
}
