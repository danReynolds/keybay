import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/clean_tool_repo.dart';

const _nonce =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  late Directory temp;
  late String repo;
  late File archive;
  late String subject;
  late File results;
  late File installer;
  late Directory cleanToolRepo;
  late String receiptScript;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('keybay-receipt-test.');
    final chmod = Process.runSync('/bin/chmod', ['700', temp.path]);
    if (chmod.exitCode != 0) {
      throw StateError('could not make the receipt test directory private');
    }
    repo = Directory.current.path;
    cleanToolRepo = await stageCleanToolRepo(temp, repo, const [
      'tool/compare_pub_archives.py',
      'tool/device_security/catalog.dart',
      'tool/device_security/receipt.dart',
    ]);
    receiptScript = '${cleanToolRepo.path}/tool/device_security/receipt.dart';
    final package = Directory('${temp.path}/package')..createSync();
    File('${package.path}/pubspec.yaml')
        .writeAsStringSync('name: keybay\nversion: 1.2.3\n');
    final lib = Directory('${package.path}/lib')..createSync();
    File('${lib.path}/keybay.dart').writeAsStringSync('library;\n');
    archive = File('${temp.path}/keybay-1.2.3.tar.gz');
    final tar = await Process.run('tar', [
      '-C',
      package.path,
      '-czf',
      archive.path,
      'pubspec.yaml',
      'lib',
    ]);
    expect(tar.exitCode, 0, reason: '${tar.stderr}');
    final digest = await Process.run('python3', [
      '$repo/tool/compare_pub_archives.py',
      '--digest',
      archive.path,
    ]);
    expect(digest.exitCode, 0, reason: '${digest.stderr}');
    subject = 'core-pub-content-sha256:${(digest.stdout as String).trim()}';
    results = File('${temp.path}/results.json');
    _writeResults(results, subject: subject);
    installer = File('${temp.path}/app-debug.apk')..writeAsStringSync('apk');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> runReceipt(List<String> extra, {String? output}) =>
      Process.run(
        Platform.resolvedExecutable,
        [
          receiptScript,
          '--output',
          output ?? '${temp.path}/receipt.json',
          '--platform',
          'android',
          '--selection',
          'android-baseline',
          '--execution-class',
          'physical-device',
          '--nonce',
          _nonce,
          '--subject-archive',
          archive.path,
          '--results',
          results.path,
          '--cleanup-status',
          'pass',
          '--installer-kind',
          'apk-sha256',
          '--installer-path',
          installer.path,
          '--package-id',
          'dev.keybay.securityharness',
          '--install-command',
          'adb-install-pull-verified',
          '--install-status',
          'pass',
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
          ...extra,
        ],
        workingDirectory: repo,
      );

  test('derives a schema-v2 pass from exact subject and structured results',
      () async {
    final result = await runReceipt([]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final receipt = jsonDecode(
      File('${temp.path}/receipt.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(receipt['schema_version'], 2);
    expect(receipt['status'], 'pass');
    expect(receipt['run_nonce'], _nonce);
    expect(receipt['suite'], containsPair('clean', true));
    expect(receipt['subject'], containsPair('sha256', subject.split(':').last));
    expect(receipt['installer'], {
      'kind': 'apk-sha256',
      'sha256':
          'dd37c2d7274f7ea982cb83390c36918fee9ce8889073c44b68cdc00bdb8c3e04',
      'package_id': 'dev.keybay.securityharness',
      'command': 'adb-install-pull-verified',
      'status': 'pass',
    });
    expect(
      (receipt['scenarios'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .every((entry) => entry['status'] == 'pass'),
      isTrue,
    );
  });

  test('result parser binds nonce/subject and derives per-scenario outcomes',
      () async {
    final raw = File('${temp.path}/raw.jsonl');
    raw.writeAsStringSync([
      _event('testStart', {
        'test': {
          'id': 1,
          'name': 'KEYBAY-SECURITY-METADATA nonce=$_nonce subject=$subject',
        }
      }),
      _event('testDone', {'testID': 1, 'result': 'success', 'skipped': false}),
      for (var index = 0; index < 3; index++) ...[
        _event('testStart', {
          'test': {
            'id': index + 2,
            'name': 'group ${[
              'KB-AND-010',
              'KB-AND-011',
              'KB-AND-020'
            ][index]} test',
          }
        }),
        _event('testDone', {
          'testID': index + 2,
          'result': index == 1 ? 'failure' : 'success',
          'skipped': false,
        }),
      ],
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
      subject,
    ]);
    expect(parsed.exitCode, 0, reason: '${parsed.stderr}');
    final document =
        jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
    expect(document['nonce'], _nonce);
    expect(document['subject'], subject);
    expect(
      (document['scenarios'] as List<dynamic>).any(
        (entry) =>
            entry is Map<String, dynamic> &&
            entry['id'] == 'KB-AND-011' &&
            entry['status'] == 'fail' &&
            entry['reason'] == 'derived from Flutter JSON test reporter',
      ),
      isTrue,
    );
  });

  test('rejects stale/substituted/omitted results and output overwrite',
      () async {
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (json) => json['nonce'] = List.filled(64, 'f').join(),
      (json) => json['subject'] =
          'core-pub-content-sha256:${List.filled(64, 'a').join()}',
      (json) => (json['scenarios'] as List<dynamic>).removeLast(),
    ]) {
      final document = jsonDecode(results.readAsStringSync());
      mutation(document as Map<String, dynamic>);
      results.writeAsStringSync(jsonEncode(document));
      final result = await runReceipt([],
          output: '${temp.path}/${mutation.hashCode}.json');
      expect(result.exitCode, 64);
      _writeResults(results, subject: subject);
    }
    File('${temp.path}/receipt.json').writeAsStringSync('existing');
    expect((await runReceipt([])).exitCode, 64);
  });

  test('failed oracle or cleanup cannot become pass', () async {
    _writeResults(results, subject: subject, failed: 'KB-AND-011');
    final failed = await runReceipt([]);
    expect(failed.exitCode, 0, reason: '${failed.stderr}');
    expect(
      (jsonDecode(File('${temp.path}/receipt.json').readAsStringSync())
          as Map<String, dynamic>)['status'],
      'fail',
    );

    _writeResults(results, subject: subject);
    final args = await _baseArgsForCleanupFailure(
        receiptScript, temp, archive, results, installer);
    final cleanup = await Process.run(Platform.resolvedExecutable, args,
        workingDirectory: repo);
    expect(cleanup.exitCode, 0, reason: '${cleanup.stderr}');
    expect(
      (jsonDecode(File('${temp.path}/cleanup.json').readAsStringSync())
          as Map<String, dynamic>)['status'],
      'inconclusive',
    );
  });

  test('dirty suite source cannot issue a release receipt', () async {
    File('${cleanToolRepo.path}/tool/device_security/catalog.dart')
        .writeAsStringSync('\n', mode: FileMode.append);
    expect(
      (await runReceipt([], output: '${temp.path}/dirty.json')).exitCode,
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
          hasLength(1));
    }
    for (final match in RegExp(r'`(KB-INV-[0-9]+)`').allMatches(generated)) {
      final id = match.group(1)!;
      expect(
          RegExp('^\\| `${RegExp.escape(id)}` \\|', multiLine: true)
              .allMatches(design),
          hasLength(1));
    }
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
    expect(RegExp(r'<exclude domain="file" path="\."\s*/>').allMatches(rules),
        hasLength(2));
    expect(rules, isNot(contains('<cross-platform-transfer platform="ios">')));

    final config = File(
      '$repo/example_flutter/macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    expect(config,
        contains('PRODUCT_BUNDLE_IDENTIFIER = dev.keybay.securityharness'));
  });
}

void _writeResults(File file, {required String subject, String? failed}) {
  file.writeAsStringSync(jsonEncode({
    'schema': 'keybay.device-security-results',
    'schema_version': 1,
    'nonce': _nonce,
    'subject': subject,
    'selection': 'android-baseline',
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

Future<List<String>> _baseArgsForCleanupFailure(
  String receiptScript,
  Directory temp,
  File archive,
  File results,
  File installer,
) async =>
    [
      receiptScript,
      '--output',
      '${temp.path}/cleanup.json',
      '--platform',
      'android',
      '--selection',
      'android-baseline',
      '--execution-class',
      'physical-device',
      '--nonce',
      _nonce,
      '--subject-archive',
      archive.path,
      '--results',
      results.path,
      '--cleanup-status',
      'fail',
      '--installer-kind',
      'apk-sha256',
      '--installer-path',
      installer.path,
      '--package-id',
      'dev.keybay.securityharness',
      '--install-command',
      'adb-install-pull-verified',
      '--install-status',
      'pass',
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
    ];
