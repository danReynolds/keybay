import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/clean_tool_repo.dart';

const _nonce =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  late Directory temp;
  late String repo;
  late Directory cleanToolRepo;
  late String reportScript;
  late String source;
  late File results;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('keybay-report-test.');
    final chmod = Process.runSync('/bin/chmod', ['700', temp.path]);
    if (chmod.exitCode != 0) {
      throw StateError('could not make the report test directory private');
    }
    repo = Directory.current.path;
    cleanToolRepo = await stageCleanToolRepo(temp, repo, const [
      'tool/device_security/catalog.dart',
      'tool/device_security/report.dart',
    ]);
    reportScript = '${cleanToolRepo.path}/tool/device_security/report.dart';
    final commit = Process.runSync(
      'git',
      ['-C', cleanToolRepo.path, 'rev-parse', 'HEAD'],
    );
    expect(commit.exitCode, 0, reason: '${commit.stderr}');
    source = 'git-commit:${(commit.stdout as String).trim()}';
    results = File('${temp.path}/results.json');
    _writeResults(results, source: source);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> runReport(
    List<String> extra, {
    String? output,
    String commandStatus = 'pass',
    String cleanupStatus = 'pass',
  }) =>
      Process.run(
        Platform.resolvedExecutable,
        [
          reportScript,
          '--output',
          output ?? '${temp.path}/report.json',
          '--platform',
          'android',
          '--selection',
          'android-baseline',
          '--execution-class',
          'physical-device',
          '--nonce',
          _nonce,
          '--results',
          results.path,
          '--command-status',
          commandStatus,
          '--cleanup-status',
          cleanupStatus,
          '--field',
          'model=Google Pixel',
          '--field',
          'osVersion=16',
          '--field',
          'apiLevel=36',
          '--field',
          'securityPatch=2026-08-05',
          '--field',
          'buildFingerprint=google/device/build',
          '--field',
          'verifiedBoot=green; vbmeta=locked; flash-locked=1',
          '--field',
          'selinux=Enforcing',
          '--field',
          'fbe=native',
          '--limitation',
          'One physical device configuration.',
          ...extra,
        ],
        workingDirectory: repo,
      );

  test('records one clean source-scoped physical configuration', () async {
    final result = await runReport([]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final report = jsonDecode(
      File('${temp.path}/report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(report['schema'], 'keybay.device-security-report');
    expect(report['schema_version'], 1);
    expect(report['status'], 'pass');
    expect(report['source'], {
      'commit': source.split(':').last,
      'clean': true,
    });
    expect(report, isNot(contains('subject')));
    expect(report, isNot(contains('installer')));
    expect(report['limitations'], ['One physical device configuration.']);
    expect(
      (report['scenarios'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .every((entry) => entry['status'] == 'pass'),
      isTrue,
    );
  });

  test('parser prevents an aggregate Flutter failure from becoming a pass',
      () async {
    final raw = File('${temp.path}/raw.jsonl');
    raw.writeAsStringSync([
      _event('testStart', {
        'test': {
          'id': 1,
          'name': 'KEYBAY-SECURITY-METADATA nonce=$_nonce subject=$source',
        },
      }),
      _event('testDone', {'testID': 1, 'result': 'success', 'skipped': false}),
      for (var index = 0; index < 3; index++) ...[
        _event('testStart', {
          'test': {
            'id': index + 2,
            'name': 'group ${[
              'KB-AND-010',
              'KB-AND-011',
              'KB-AND-020',
            ][index]} test',
          },
        }),
        _event('testDone', {
          'testID': index + 2,
          'result': 'success',
          'skipped': false,
        }),
      ],
      _event('done', {'success': false}),
    ].join('\n'));
    final output = File('${temp.path}/parsed.json');
    final parsed = await Process.run(Platform.resolvedExecutable, [
      '$repo/tool/device_security/result.dart',
      '--input',
      raw.path,
      '--output',
      output.path,
      '--selection',
      'android-baseline',
      '--nonce',
      _nonce,
      '--subject',
      source,
    ]);
    expect(parsed.exitCode, 0, reason: '${parsed.stderr}');
    final document =
        jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
    expect(document['schema_version'], 2);
    expect(document['command_status'], 'fail');
    expect(
      (document['scenarios'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .every((entry) => entry['status'] == 'pass'),
      isTrue,
    );
  });

  test('failed command or cleanup cannot become a pass report', () async {
    _writeResults(results, source: source, failed: 'KB-AND-011');
    final scenario = await runReport(
      [],
      output: '${temp.path}/scenario.json',
    );
    expect(scenario.exitCode, 0, reason: '${scenario.stderr}');
    expect(
      (jsonDecode(File('${temp.path}/scenario.json').readAsStringSync())
          as Map<String, dynamic>)['status'],
      'fail',
    );

    _writeResults(results, source: source, commandStatus: 'fail');
    final command = await runReport(
      [],
      commandStatus: 'fail',
      output: '${temp.path}/command.json',
    );
    expect(command.exitCode, 0, reason: '${command.stderr}');
    expect(
      (jsonDecode(File('${temp.path}/command.json').readAsStringSync())
          as Map<String, dynamic>)['status'],
      'inconclusive',
    );

    _writeResults(results, source: source);
    final cleanup = await runReport(
      [],
      cleanupStatus: 'fail',
      output: '${temp.path}/cleanup.json',
    );
    expect(cleanup.exitCode, 0, reason: '${cleanup.stderr}');
    expect(
      (jsonDecode(File('${temp.path}/cleanup.json').readAsStringSync())
          as Map<String, dynamic>)['status'],
      'inconclusive',
    );
  });

  test('rejects substituted source, dirty source, identifiers, and overwrite',
      () async {
    _writeResults(
      results,
      source: 'git-commit:${List.filled(40, 'a').join()}',
    );
    expect(
      (await runReport([], output: '${temp.path}/substituted.json')).exitCode,
      64,
    );
    _writeResults(results, source: source);
    expect(
      (await runReport(
        ['--field', 'deviceId=private'],
        output: '${temp.path}/identifier.json',
      ))
          .exitCode,
      64,
    );
    File('${temp.path}/report.json').writeAsStringSync('existing');
    expect((await runReport([])).exitCode, 64);

    File('${cleanToolRepo.path}/tool/device_security/catalog.dart')
        .writeAsStringSync('\n', mode: FileMode.append);
    expect(
      (await runReport([], output: '${temp.path}/dirty.json')).exitCode,
      64,
    );
  });

  test('catalog inventory, procedures, and normative guarantees agree',
      () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['$repo/tool/device_security/catalog.dart', 'markdown'],
      workingDirectory: repo,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final generated = (result.stdout as String).trim();
    final suite = File('$repo/doc/device-security-suite.md').readAsStringSync();
    final block = RegExp(
      r'<!-- BEGIN GENERATED DEVICE SECURITY INVENTORY -->\n([\s\S]*?)\n<!-- END GENERATED DEVICE SECURITY INVENTORY -->',
    ).firstMatch(suite);
    expect(block!.group(1)!.trim(), generated);
    final design = File('$repo/doc/design.md').readAsStringSync();
    for (final match in RegExp(r'^\| `(KB-[A-Z]+-[0-9]+)` \|', multiLine: true)
        .allMatches(generated)) {
      final id = match.group(1)!;
      expect(
        RegExp('^### `${RegExp.escape(id)}`\$', multiLine: true)
            .allMatches(suite),
        hasLength(1),
      );
    }
    for (final match in RegExp(r'`(KB-INV-[0-9]+)`').allMatches(generated)) {
      final id = match.group(1)!;
      expect(
        RegExp('^\\| `${RegExp.escape(id)}` \\|', multiLine: true)
            .allMatches(design),
        hasLength(1),
      );
    }
  });

  test('iOS selector records model and OS without the raw device ID', () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['$repo/tool/device_security/flutter_device.dart', 'private-device-id'],
      workingDirectory: repo,
    );
    process.stdin.write(jsonEncode([
      {
        'id': 'private-device-id',
        'name': 'iPhone 17 Pro',
        'targetPlatform': 'ios',
        'emulator': false,
        'isSupported': true,
        'sdk': 'iOS 26.1',
      },
    ]));
    await process.stdin.close();
    final stdoutText = await utf8.decoder.bind(process.stdout).join();
    final stderrText = await utf8.decoder.bind(process.stderr).join();
    expect(await process.exitCode, 0, reason: stderrText);
    expect(stdoutText.trim(), 'iPhone 17 Pro\tiOS 26.1');
    expect(stdoutText, isNot(contains('private-device-id')));
  });

  test('entrypoint and platform adapters retain destructive safety guards',
      () async {
    final traversal = await Process.run(
      'bash',
      ['$repo/tool/device_security.sh', 'doctor', '../device_security/linux'],
      workingDirectory: repo,
    );
    expect(traversal.exitCode, 64);

    final android =
        File('$repo/tool/device_security/android.sh').readAsStringSync();
    expect(android, contains(r'uninstall --user "$ANDROID_USER"'));
    expect(android, contains(r'--device-user "$ANDROID_USER"'));
    expect(android, isNot(contains('_android_controlled_install')));
    expect(android, contains('exit 130'));
    expect(android, contains('exit 143'));
  });

  test('host backup exclusions and macOS identity stay harness-scoped', () {
    final manifest = File(
      '$repo/example_flutter/android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    final rules = File(
      '$repo/example_flutter/android/app/src/main/res/xml/'
      'data_extraction_rules.xml',
    ).readAsStringSync();
    expect(
      RegExp(r'<exclude domain="file" path="\."\s*/>').allMatches(rules),
      hasLength(2),
    );
    expect(rules, isNot(contains('<cross-platform-transfer platform="ios">')));

    final config = File(
      '$repo/example_flutter/macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    expect(
      config,
      contains('PRODUCT_BUNDLE_IDENTIFIER = dev.keybay.securityharness'),
    );
  });
}

void _writeResults(
  File file, {
  required String source,
  String commandStatus = 'pass',
  String? failed,
}) {
  file.writeAsStringSync(jsonEncode({
    'schema': 'keybay.device-security-results',
    'schema_version': 2,
    'nonce': _nonce,
    'subject': source,
    'selection': 'android-baseline',
    'command_status': commandStatus,
    'scenarios': [
      for (final id in ['KB-AND-010', 'KB-AND-011', 'KB-AND-020'])
        {
          'id': id,
          'status': id == failed ? 'fail' : 'pass',
          'reason': 'derived from Flutter JSON test reporter',
        },
    ],
  }));
}

String _event(String type, Map<String, Object> fields) =>
    jsonEncode({'type': type, ...fields});
