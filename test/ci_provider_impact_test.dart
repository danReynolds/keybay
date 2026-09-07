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
    final impact = classifyProviderImpact([
      'packages/keybay/lib/src/v2/framed_store_reader.dart',
    ]);
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
      'example_flutter/integration_test/keybay_v2_ios_test.dart',
    ]);
    expect(impact.macos, isFalse);
    expect(impact.linux, isFalse);
    expect(impact.android, isTrue);
    expect(impact.ios, isTrue);
  });

  test('V2 Linux harness changes exercise the Linux provider', () {
    for (final path in [
      'packages/keybay/test/v2_linux_secret_service_integration_test.dart',
      'packages/keybay/test/support/linux_public_facade_app/main.dart',
      'tool/test_linux.sh',
      'tool/test_linux_docker.sh',
      'tool/linux_test.Dockerfile',
    ]) {
      final impact = classifyProviderImpact([path]);
      expect(impact.macos, isFalse);
      expect(impact.linux, isTrue);
      expect(impact.android, isFalse);
      expect(impact.ios, isFalse);
    }
  });

  test('native macOS harness changes exercise the macOS provider', () {
    for (final path in [
      'packages/keybay/test/v2_macos_locked_integration_test.dart',
      'packages/keybay/test/support/macos_locked_store_worker.dart',
      'tool/test_macos_native.sh',
      'tool/test_macos_signed.sh',
      'tool/macos_test_keychain.c',
    ]) {
      final impact = classifyProviderImpact([path]);
      expect(impact.macos, isTrue);
      expect(impact.linux, isFalse);
      expect(impact.android, isFalse);
      expect(impact.ios, isFalse);
    }
  });

  test('core version changes exercise every supported provider', () {
    final impact = classifyProviderImpact(const [], coreVersionChanged: true);
    expect(impact.macos, isTrue);
    expect(impact.linux, isTrue);
    expect(impact.android, isTrue);
    expect(impact.ios, isTrue);
  });

  test('Flatpak harness changes exercise the native Linux lanes', () {
    for (final path in [
      'packages/keybay/test/v2_flatpak_host_platform_test.dart',
      'packages/keybay/test/v2_flatpak_secret_portal_protector_test.dart',
      'packages/keybay/test/support/flatpak_native_harness.dart',
      'tool/test_flatpak.sh',
    ]) {
      final impact = classifyProviderImpact([path]);
      expect(impact.linux, isTrue);
      expect(impact.macos, isFalse);
      expect(impact.android, isFalse);
      expect(impact.ios, isFalse);
    }
  });

  test('CLI version changes exercise its release providers', () {
    final impact = classifyProviderImpact(const [], cliVersionChanged: true);
    expect(impact.macos, isTrue);
    expect(impact.linux, isTrue);
    expect(impact.android, isFalse);
    expect(impact.ios, isFalse);
  });

  test('workflow and manual runs exercise every provider', () {
    for (final impact in [
      classifyProviderImpact(['.github/workflows/ci.yml']),
      classifyProviderImpact(['tool/platform_regression.dart']),
      classifyProviderImpact(['tool/test_e2e.sh']),
      classifyProviderImpact(['tool/test_core.sh']),
      classifyProviderImpact(const [], forceAll: true),
    ]) {
      expect(impact.macos, isTrue);
      expect(impact.linux, isTrue);
      expect(impact.android, isTrue);
      expect(impact.ios, isTrue);
    }
  });
}
