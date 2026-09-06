import 'dart:convert';
import 'dart:io';

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

Future<void> main(List<String> arguments) async {
  const usage =
      '''Usage: ./tool/test_e2e.sh [all | core macos linux flatpak android ios]
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
  final selected =
      arguments.isEmpty || (arguments.length == 1 && arguments.single == 'all')
      ? _routine
      : arguments.toSet().toList();
  if (selected.any((name) => !_scripts.containsKey(name))) {
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
  final head = await Process.run('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: root);
  final status = await Process.run('git', [
    'status',
    '--porcelain',
  ], workingDirectory: root);
  final results = <Map<String, Object?>>[
    for (final platform in selected)
      {'platform': platform, 'status': 'not-run', 'exitCode': null},
  ];
  final report = <String, Object?>{
    'kind': 'sdk-regression',
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceCommit': head.exitCode == 0 ? (head.stdout as String).trim() : null,
    'sourceDirty': status.exitCode == 0
        ? (status.stdout as String).isNotEmpty
        : null,
    'host': Platform.operatingSystem,
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
      final command = ['bash', ..._scripts[platform]!];
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
  stdout.writeln('\nSDK regression: ${report['status']}');
  for (final result in results) {
    stdout.writeln('  ${result['platform']}: ${result['status']}');
  }
  stdout.writeln('Regression report: ${reportFile.path}');
  exitCode = failed ? 1 : (blocked ? 69 : 0);
}
