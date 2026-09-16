import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _routine = ['core', 'macos', 'linux', 'flatpak', 'android', 'ios'];
const _scripts = {
  'core': ['tool/test_core.sh'],
  'macos': ['tool/test_macos_native.sh'],
  'linux': ['tool/test_linux.sh'],
  'flatpak': ['tool/test_flatpak.sh'],
  'android': ['tool/test_mobile_ci.sh', 'android'],
  'ios': ['tool/test_mobile_ci.sh', 'ios'],
  'macos-signed': ['tool/test_macos_signed.sh'],
  'macos-developer-id': ['tool/test_macos_developer_id.sh'],
};

const _cliScripts = {
  'core': ['tool/test_cli_core.sh'],
  'macos': ['tool/test_cli_platform.sh', 'macos'],
  'linux': ['tool/test_cli_platform.sh', 'linux'],
};

Future<void> main(List<String> input) async {
  final cli = input.isNotEmpty && input.first == '--cli';
  final arguments = cli ? input.sublist(1) : input;
  final scripts = cli ? _cliScripts : _scripts;
  final routine = cli ? ['core', 'macos', 'linux'] : _routine;
  final product = cli ? 'CLI' : 'SDK';
  final usage = cli
      ? '''Usage: ./tool/test_cli.sh [core | macos | linux | all]
Supply one or more names; no arguments means core (no real store).
core runs command, SDK-boundary, TUI/PTY, clipboard, exec and archive checks.
macos/linux run real-provider flows with disposable identities; Linux runs in
Docker on macOS. Missing prerequisites are blocked (69), not passed.
Reports in build/regression distinguish CLI from SDK results. These checks do
not qualify signed distribution/upgrade/notarization.'''
      : '''Usage: ./tool/test_e2e.sh [all | core macos linux flatpak android ios]
       ./tool/test_e2e.sh macos-signed
       ./tool/test_e2e.sh macos-developer-id

No arguments means all routine SDK regressions. Supply one or more names for a
subset. Android uses a ready emulator; iOS uses a simulator. On macOS, Linux
and Flatpak run in Docker. macos-signed is opt-in and needs KEYBAY_APPLE_TEAM_ID.
macos-developer-id is opt-in and needs a Developer ID Application identity.
Physical-device procedures remain in tool/device_security.sh.

Every selected lane must pass for exit 0. Missing prerequisites are blocked
(exit 69); failures exit 1. Reports in build/regression are regression results,
not physical-device or release qualification.''';
  if (arguments.length == 1 && arguments.single == '--help') {
    stdout.writeln(usage);
    return;
  }
  final selected = arguments.isEmpty
      ? (cli ? ['core'] : routine)
      : (arguments.length == 1 && arguments.single == 'all')
      ? routine
      : arguments.toSet().toList();
  if (selected.any((name) => !scripts.containsKey(name))) {
    stderr.writeln(usage);
    exitCode = 64;
    return;
  }

  final root = File.fromUri(Platform.script).parent.parent.path;
  final output = Directory('$root/build/regression');
  output.createSync(recursive: true);
  final run = output.createTempSync('run-');
  // Reports contain no device identifiers or raw tool output.
  if (!Platform.isWindows) {
    final permissions = await Process.run('chmod', ['700', run.path]);
    if (permissions.exitCode != 0) throw StateError('Cannot protect report');
  }
  final head = await _gitOutput(root, ['rev-parse', 'HEAD']);
  final status = await _gitOutput(root, ['status', '--porcelain']);
  final results = <Map<String, Object?>>[
    for (final platform in selected)
      {'platform': platform, 'status': 'not-run', 'exitCode': null},
  ];
  final report = <String, Object?>{
    'kind': cli ? 'cli-regression' : 'sdk-regression',
    if (cli) 'sourceDigest': _cliSourceDigest(root),
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceCommit': head?.trim(),
    'sourceDirty': status?.isNotEmpty,
    'host': Platform.operatingSystem,
    'dartAbi': Abi.current().toString(),
    'dart': Platform.version.split(' ').first,
    'status': 'incomplete',
    'results': results,
  };
  final reportFile = File('${run.path}/report.json');
  void save() {
    final staged = File('${run.path}/report.tmp');
    staged.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    staged.renameSync(reportFile.path);
  }

  save();
  stdout.writeln('Regression report: ${reportFile.path}');
  var failed = false;
  var blocked = false;
  for (final result in results) {
    final platform = result['platform']! as String;
    stdout.writeln('\n== $platform ==');
    result['status'] = 'running';
    save();
    var code = 69;
    if ((platform == 'macos' ||
            platform == 'macos-signed' ||
            platform == 'macos-developer-id' ||
            platform == 'ios') &&
        !Platform.isMacOS) {
      stderr.writeln('$platform requires macOS.');
    } else {
      final command = ['bash', ...scripts[platform]!];
      try {
        final child = await Process.start(
          command.first,
          command.skip(1).toList(),
          workingDirectory: root,
          mode: ProcessStartMode.inheritStdio,
          environment: {'KEYBAY_REGRESSION_DIR': run.path},
        );
        code = await child.exitCode;
      } on ProcessException catch (error) {
        stderr.writeln('Could not start $platform: ${error.message}');
        code = error.errorCode == 2 ? 69 : 1;
      }
    }
    if (cli && platform == 'linux') {
      final nested = File('${run.path}/cli-linux.json');
      if (nested.existsSync()) {
        result['linuxReport'] = jsonDecode(nested.readAsStringSync());
      }
    }
    result['exitCode'] = code;
    result['status'] = code == 0 ? 'pass' : (code == 69 ? 'blocked' : 'fail');
    blocked |= code == 69;
    failed |= code != 0 && code != 69;
    save();
    if (code == 130 || code == 143 || code < 0) {
      report['status'] = 'interrupted';
      save();
      exitCode = code == 143 ? 143 : 130;
      return;
    }
  }
  report['status'] = failed ? 'fail' : (blocked ? 'blocked' : 'pass');
  report['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
  save();
  stdout.writeln('\n$product regression: ${report['status']}');
  for (final result in results) {
    stdout.writeln('  ${result['platform']}: ${result['status']}');
  }
  stdout.writeln('Regression report: ${reportFile.path}');
  exitCode = failed ? 1 : (blocked ? 69 : 0);
}

// Hash the command, SDK dependency and regression sources in both native and
// copied Docker checkouts. Tests do not depend on Git metadata being present.
String _cliSourceDigest(String root) {
  final files = <File>[
    for (final name in [
      'pubspec.yaml',
      'pubspec.lock',
      'packages/keybay/pubspec.yaml',
      'packages/keybay_cli/pubspec.yaml',
      'packages/keybay_cli/dart_test.yaml',
      'analysis_options.yaml',
    ])
      File('$root/$name'),
    for (final name in [
      'packages/keybay/lib',
      'packages/keybay/test/support',
      'packages/keybay_cli/lib',
      'packages/keybay_cli/bin',
      'packages/keybay_cli/test',
      'packages/keybay_cli/tool',
      'tool',
    ])
      ...Directory('$root/$name')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => !file.path.contains('/__pycache__/')),
  ]..sort((a, b) => a.path.compareTo(b.path));
  final inventory = StringBuffer();
  for (final file in files) {
    inventory.writeln(
      '${file.path.substring(root.length + 1)} ${sha256.convert(file.readAsBytesSync())}',
    );
  }
  return sha256.convert(utf8.encode(inventory.toString())).toString();
}

Future<String?> _gitOutput(String root, List<String> arguments) async {
  try {
    final result = await Process.run('git', arguments, workingDirectory: root);
    return result.exitCode == 0 ? result.stdout as String : null;
  } on ProcessException {
    return null; // Copied Docker sources carry the content digest instead.
  }
}
