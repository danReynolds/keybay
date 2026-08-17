import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/security_assurance/manifest.dart' show receiptSemanticsPaths;
import 'support/clean_tool_repo.dart';

void main() {
  late Directory temp;
  late String repo;
  late File archive;
  late String digest;
  late File evidence;
  late File receipt;
  late Directory cleanToolRepo;
  late String manifestScript;
  late String cleanToolCommit;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('keybay-manifest-test.');
    repo = Directory.current.path;
    cleanToolRepo = await stageCleanToolRepo(temp, repo, const [
      'tool/compare_pub_archives.py',
      'tool/device_security/catalog.dart',
      'tool/security_assurance/manifest.dart',
    ]);
    manifestScript =
        '${cleanToolRepo.path}/tool/security_assurance/manifest.dart';
    final commit = await Process.run(
      '/usr/bin/git',
      ['-C', cleanToolRepo.path, 'rev-parse', 'HEAD'],
    );
    expect(commit.exitCode, 0, reason: '${commit.stderr}');
    cleanToolCommit = (commit.stdout as String).trim();
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
    final identity = await Process.run('python3', [
      '$repo/tool/compare_pub_archives.py',
      '--digest',
      archive.path,
    ]);
    expect(identity.exitCode, 0, reason: '${identity.stderr}');
    digest = (identity.stdout as String).trim();
    evidence = File('${temp.path}/results.json')..writeAsStringSync('{}');
    final evidenceDigest = (await Process.run(
      '/usr/bin/shasum',
      ['-a', '256', evidence.path],
    ))
        .stdout
        .toString()
        .split(RegExp(r'\s+'))
        .first;
    receipt = File('${temp.path}/android.receipt.json')
      ..writeAsStringSync(jsonEncode({
        'schema': 'keybay.device-security-receipt',
        'schema_version': 2,
        'timestamp': '2026-08-16T20:00:00.000Z',
        'status': 'pass',
        'platform': 'android',
        'selection': 'android-tamper',
        'execution_class': 'physical-device',
        'suite': {
          'commit': cleanToolCommit,
          'clean': true,
        },
        'run_nonce': List.filled(64, '2').join(),
        'subject': {
          'kind': 'core-pub-content-sha256',
          'sha256': digest,
        },
        'installer': {
          'kind': 'apk-sha256',
          'sha256': List.filled(64, '3').join(),
          'package_id': 'dev.keybay.securityharness',
          'command': 'adb-install-pull-verified',
          'status': 'pass',
        },
        'cleanup': {'status': 'pass'},
        'scenarios': [
          for (final id in [
            'KB-AND-001',
            'KB-AND-010',
            'KB-AND-011',
            'KB-AND-020',
            'KB-AND-030',
            'KB-AND-040',
          ])
            {'id': id, 'status': 'pass'},
        ],
        'evidence': [
          {
            'path': 'results.json',
            'sha256': evidenceDigest,
            'bytes': evidence.lengthSync(),
          },
        ],
      }));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> runManifest({
    List<String> extra = const [],
    String? output,
    String version = '1.2.3',
    bool withReceipt = true,
    bool withAndroidGap = false,
  }) =>
      Process.run(
        Platform.resolvedExecutable,
        [
          manifestScript,
          '--output',
          output ?? '${temp.path}/manifest.json',
          '--subject',
          'core',
          '--version',
          version,
          '--ci-run-id',
          '12345',
          '--artifact',
          'keybay-1.2.3.tar.gz=${archive.path}',
          if (withReceipt) ...['--receipt', receipt.path],
          if (withReceipt) ...['--require-selection', 'android-tamper'],
          if (withAndroidGap) ...[
            '--unqualified',
            'Android device qualification was not re-run for this patch release',
          ],
          '--unqualified',
          'macOS native-host qualification was not re-run for this release',
          '--unqualified',
          'Physical Apple qualification has not been performed',
          '--limitation',
          'https://github.com/danReynolds/keybay/blob/main/SECURITY.md',
          ...extra,
        ],
        workingDirectory: repo,
      );

  test('assembles a scoped core manifest from matching retained evidence',
      () async {
    final result = await runManifest();
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final manifest = jsonDecode(
      File('${temp.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['schema_version'], 1);
    expect(manifest['subject'], 'keybay-core');
    expect(manifest['version'], '1.2.3');
    expect(
      (manifest['artifacts'] as List<dynamic>).single,
      containsPair('sha256', digest),
    );
    expect(
      (manifest['qualification_receipts'] as List<dynamic>).single,
      containsPair('selection', 'android-tamper'),
    );
  });

  test('rejects substituted receipt subjects and unresolved evidence',
      () async {
    final original =
        jsonDecode(receipt.readAsStringSync()) as Map<String, dynamic>;
    (original['subject'] as Map<String, dynamic>)['sha256'] =
        List.filled(64, 'a').join();
    receipt.writeAsStringSync(jsonEncode(original));
    expect((await runManifest()).exitCode, 64);

    (original['subject'] as Map<String, dynamic>)['sha256'] = digest;
    receipt.writeAsStringSync(jsonEncode(original));
    evidence.deleteSync();
    expect(
      (await runManifest(output: '${temp.path}/missing-evidence.json'))
          .exitCode,
      64,
    );
  });

  test('CLI manifest binds exact archive bytes without device receipts',
      () async {
    final binaryArchive = File('${temp.path}/cli.tar.gz')
      ..writeAsStringSync('cli bytes');
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        manifestScript,
        '--output',
        '${temp.path}/cli.json',
        '--subject',
        'cli',
        '--version',
        '1.2.3',
        '--ci-run-id',
        '12345',
        '--artifact',
        'keybay-1.2.3-linux-x64.tar.gz=${binaryArchive.path}',
        '--unqualified',
        'No independent third-party assessment has been completed',
      ],
      workingDirectory: repo,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final manifest =
        jsonDecode(File('${temp.path}/cli.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['subject'], 'keybay-cli');
    expect(manifest['qualification_receipts'], isEmpty);
  });

  test('dirty suite source cannot issue a release manifest', () async {
    File('${cleanToolRepo.path}/tool/security_assurance/manifest.dart')
        .writeAsStringSync('\n', mode: FileMode.append);
    expect(
      (await runManifest(output: '${temp.path}/dirty.json')).exitCode,
      64,
    );
  });

  test('receipt cannot carry across a later runner or oracle change', () async {
    File('${cleanToolRepo.path}/tool/device_security/changed-after-receipt.txt')
        .writeAsStringSync('invalidate receipt reuse\n');
    for (final arguments in [
      ['add', '--all'],
      ['commit', '--quiet', '-m', 'change runner after receipt'],
    ]) {
      final result = await Process.run(
        '/usr/bin/git',
        ['-C', cleanToolRepo.path, ...arguments],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    expect(
      (await runManifest(output: '${temp.path}/invalid-reuse.json')).exitCode,
      64,
    );
  });

  test('changes outside suite semantics do not invalidate a receipt', () async {
    // The subject digest pins the tested package bytes; a docs-only commit
    // after the receipt must not force a redundant device run.
    Directory('${cleanToolRepo.path}/doc').createSync(recursive: true);
    File('${cleanToolRepo.path}/doc/notes.md')
        .writeAsStringSync('unrelated docs change\n');
    for (final arguments in [
      ['add', '--all'],
      ['commit', '--quiet', '-m', 'docs change after receipt'],
    ]) {
      final result = await Process.run(
        '/usr/bin/git',
        ['-C', cleanToolRepo.path, ...arguments],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    final result = await runManifest(output: '${temp.path}/docs-change.json');
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('required baseline is satisfied by a superset tamper receipt', () async {
    final result = await runManifest(
      output: '${temp.path}/superset.json',
      extra: ['--require-selection', 'android-baseline'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('core policy is enforced by the validator, not the wrapper', () async {
    // A minor/major (x.y.0) without an Android receipt fails even when no
    // caller passes --require-selection.
    expect(
      (await runManifest(
        output: '${temp.path}/minor-missing.json',
        version: '1.3.0',
        withReceipt: false,
      ))
          .exitCode,
      64,
    );
    // A patch without an Android receipt must declare the gap...
    expect(
      (await runManifest(
        output: '${temp.path}/patch-undeclared.json',
        withReceipt: false,
      ))
          .exitCode,
      64,
    );
    // ...and passes once it does.
    expect(
      (await runManifest(
        output: '${temp.path}/patch-declared.json',
        withReceipt: false,
        withAndroidGap: true,
      ))
          .exitCode,
      0,
    );
    // A receipt plus the matching gap declaration is a contradiction.
    expect(
      (await runManifest(
        output: '${temp.path}/contradiction.json',
        withAndroidGap: true,
      ))
          .exitCode,
      64,
    );
  });

  test('every receipt-semantics path still exists in the repository', () {
    for (final path in receiptSemanticsPaths) {
      final exists = path.endsWith('/')
          ? Directory('$repo/$path').existsSync()
          : File('$repo/$path').existsSync();
      expect(exists, isTrue,
          reason: '$path is named by receiptSemanticsPaths but does not '
              'exist — a renamed path silently stops invalidating receipts');
    }
  });

  test('an uncovered required selection fails the manifest', () async {
    expect(
      (await runManifest(
        output: '${temp.path}/uncovered.json',
        extra: ['--require-selection', 'ios-baseline'],
      ))
          .exitCode,
      64,
    );
    expect(
      (await runManifest(
        output: '${temp.path}/unknown.json',
        extra: ['--require-selection', 'not-a-selection'],
      ))
          .exitCode,
      64,
    );
  });
}
