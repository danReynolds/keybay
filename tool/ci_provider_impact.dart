import 'dart:io';

/// Expensive provider checks are event-driven: releases always exercise their
/// supported providers, while ordinary changes exercise only providers whose
/// implementation or harness may have changed.
final class ProviderImpact {
  const ProviderImpact({
    required this.macos,
    required this.linux,
    required this.android,
    required this.ios,
    required this.reason,
  });

  final bool macos;
  final bool linux;
  final bool android;
  final bool ios;
  final String reason;
}

ProviderImpact classifyProviderImpact(
  Iterable<String> changedPaths, {
  bool coreVersionChanged = false,
  bool cliVersionChanged = false,
  bool forceAll = false,
}) {
  final paths = changedPaths.toSet();
  final workflowChanged = paths.contains('.github/workflows/ci.yml') ||
      paths.contains('tool/ci_provider_impact.dart');
  final coreChanged = paths.any((path) =>
      path.startsWith('packages/keybay/lib/') ||
      path == 'packages/keybay/pubspec.yaml' ||
      path == 'pubspec.lock');
  final cliChanged = paths.any((path) =>
      path.startsWith('packages/keybay_cli/bin/') ||
      path.startsWith('packages/keybay_cli/lib/') ||
      path == 'packages/keybay_cli/pubspec.yaml');
  final macosHarnessChanged = paths.any((path) =>
      path == 'packages/keybay/test/keychain_integration_test.dart' ||
      path.startsWith('tool/test_cli_') ||
      path == 'tool/benchmark_cli.sh');
  final linuxHarnessChanged = paths.any((path) =>
      path.startsWith('packages/keybay/test/secret_service_') ||
      path.startsWith('tool/test_cli_') ||
      path == 'tool/benchmark_cli.sh');
  final mobileHarnessChanged = paths.any((path) =>
      path.startsWith('example_flutter/') || path == 'tool/test_mobile_ci.sh');

  final all = forceAll || workflowChanged || coreChanged || coreVersionChanged;
  final macos = all || cliChanged || cliVersionChanged || macosHarnessChanged;
  final linux = all || cliChanged || cliVersionChanged || linuxHarnessChanged;
  final android = all || mobileHarnessChanged;
  final ios = all || mobileHarnessChanged;

  final reasons = <String>[
    if (forceAll) 'manual run',
    if (coreVersionChanged) 'keybay version changed',
    if (cliVersionChanged) 'keybay_cli version changed',
    if (workflowChanged) 'provider CI changed',
    if (coreChanged) 'core implementation or dependency changed',
    if (cliChanged) 'CLI implementation changed',
    if (macosHarnessChanged || linuxHarnessChanged) 'desktop harness changed',
    if (mobileHarnessChanged) 'mobile harness changed',
  ];
  return ProviderImpact(
    macos: macos,
    linux: linux,
    android: android,
    ios: ios,
    reason:
        reasons.isEmpty ? 'no provider-sensitive change' : reasons.join('; '),
  );
}

void main(List<String> args) {
  if (args.length == 1 && args.single == '--all') {
    _printOutputs(classifyProviderImpact(const [], forceAll: true));
    return;
  }
  if (args.length != 4 || args[0] != '--base' || args[2] != '--head') {
    stderr.writeln(
      'usage: dart tool/ci_provider_impact.dart '
      '--base <git-sha> --head <git-sha> | --all',
    );
    exitCode = 64;
    return;
  }
  final base = _validatedRevision(args[1]);
  final head = _validatedRevision(args[3]);
  final changed = _git(
    ['diff', '--name-only', '--diff-filter=ACMR', base, head],
  ).split('\n').where((line) => line.isNotEmpty);
  final impact = classifyProviderImpact(
    changed,
    coreVersionChanged: _versionAt(base, 'packages/keybay/pubspec.yaml') !=
        _versionAt(head, 'packages/keybay/pubspec.yaml'),
    cliVersionChanged: _versionAt(base, 'packages/keybay_cli/pubspec.yaml') !=
        _versionAt(head, 'packages/keybay_cli/pubspec.yaml'),
  );
  _printOutputs(impact);
}

String _validatedRevision(String value) {
  if (!RegExp(r'^[0-9a-fA-F]{40,64}$').hasMatch(value)) {
    throw FormatException('invalid git revision: $value');
  }
  return value;
}

String? _versionAt(String revision, String path) {
  final result = Process.runSync('git', ['show', '$revision:$path']);
  if (result.exitCode != 0) return null;
  final match = RegExp(r'^version:\s*([^\s#]+)', multiLine: true)
      .firstMatch(result.stdout as String);
  return match?.group(1);
}

String _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      (result.stderr as String).trim(),
      result.exitCode,
    );
  }
  return result.stdout as String;
}

void _printOutputs(ProviderImpact impact) {
  stdout
    ..writeln('macos=${impact.macos}')
    ..writeln('linux=${impact.linux}')
    ..writeln('android=${impact.android}')
    ..writeln('ios=${impact.ios}')
    ..writeln('reason=${impact.reason}');
}
