import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String repo;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('keybay-receipt-test.');
    final chmod = Process.runSync('/bin/chmod', ['700', temp.path]);
    if (chmod.exitCode != 0) {
      throw StateError('could not make the receipt test directory private');
    }
    repo = Directory.current.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<ProcessResult> run(List<String> args) => Process.run(
        Platform.resolvedExecutable,
        ['$repo/tool/device_security/receipt.dart', ...args],
        workingDirectory: repo,
      );

  test('writes the allowlisted schema with a basename and SHA-256', () async {
    final evidence = File('${temp.path}/baseline.log')
      ..writeAsStringSync('abc');
    final output = '${temp.path}/receipt.json';
    final result = await run([
      '--output',
      output,
      '--platform',
      'android',
      '--selection',
      'android-baseline',
      '--execution-class',
      'physical-device',
      '--status',
      'pass',
      '--scenario',
      'KB-AND-001=pass',
      '--scenario',
      'KB-AND-010=pass',
      '--scenario',
      'KB-AND-011=pass',
      '--scenario',
      'KB-AND-020=pass',
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
      'verifiedBoot=green',
      '--field',
      'selinux=Enforcing',
      '--field',
      'fbe=native',
      '--evidence',
      evidence.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    final receipt =
        jsonDecode(File(output).readAsStringSync()) as Map<String, dynamic>;
    expect(receipt['schema'], 'keybay.device-security-receipt');
    expect(receipt['schema_version'], 1);
    expect(receipt['suite_version'], '1');
    expect(receipt['platform'], 'android');
    expect(receipt['selection'], 'android-baseline');
    expect(receipt['execution_class'], 'physical-device');
    expect(receipt['status'], 'pass');
    expect(receipt['timestamp'], isA<String>());
    expect(receipt['repository'], containsPair('dirty', isA<bool>()));
    expect(
      (receipt['repository'] as Map<String, dynamic>)['commit'],
      matches(RegExp(r'^[0-9a-f]{40}$')),
    );
    expect(receipt['device'], {
      'model': 'Google Pixel',
      'build': 'google/device/build',
      'api_level': 36,
      'security_patch': '2026-08-05',
    });
    expect(receipt['fields'], {
      'os_version': '16',
      'verified_boot': 'green',
      'selinux': 'Enforcing',
      'fbe': 'native',
    });
    expect((receipt['evidence'] as List<dynamic>).single, {
      'path': 'baseline.log',
      'sha256': 'ba7816bf8f01cfea414140de5dae2223'
          'b00361a396177a9cb410ff61f20015ad',
      'bytes': 3,
    });
  });

  test(
      'executable catalog, generated inventory, procedures, and guarantees agree',
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
    expect(block, isNotNull);
    expect(block!.group(1)!.trim(), generated);

    final ids = RegExp(r'^\| `(KB-[A-Z]+-[0-9]+)` \|', multiLine: true)
        .allMatches(generated)
        .map((match) => match.group(1)!)
        .toSet();
    expect(ids, isNotEmpty);
    for (final id in ids) {
      expect(
        RegExp('^### `${RegExp.escape(id)}`\$', multiLine: true)
            .allMatches(suite),
        hasLength(1),
        reason: '$id must have exactly one human procedure',
      );
    }

    final design = File('$repo/doc/design.md').readAsStringSync();
    final guarantees = RegExp(r'`(KB-INV-[0-9]+)`')
        .allMatches(generated)
        .map((match) => match.group(1)!)
        .toSet();
    for (final guarantee in guarantees) {
      expect(
        RegExp('^\\| `${RegExp.escape(guarantee)}` \\|', multiLine: true)
            .allMatches(design),
        hasLength(1),
        reason: '$guarantee must have exactly one normative design row',
      );
    }
  });

  test('rejects identifier-named/unknown fields and unsafe evidence names',
      () async {
    final evidence = File('${temp.path}/baseline.log')
      ..writeAsStringSync('log');
    final valid = [
      '--platform',
      'ios',
      '--selection',
      'ios-baseline',
      '--execution-class',
      'physical-device',
      '--status',
      'pass',
      '--scenario',
      'KB-IOS-001=pass',
      '--scenario',
      'KB-IOS-010=pass',
      '--scenario',
      'KB-IOS-020=pass',
      '--field',
      'osVersion=iOS 19',
      '--evidence',
      evidence.path,
    ];
    for (final field in ['deviceSerial=ABC123', 'operatorNote=hello']) {
      final result = await run([
        '--output',
        '${temp.path}/${field.hashCode}.json',
        ...valid,
        '--field',
        field,
      ]);
      expect(result.exitCode, 64);
    }
    final unsafeEvidence = File('${temp.path}/device-serial-ABC.log')
      ..writeAsStringSync('log');
    final result = await run([
      '--output',
      '${temp.path}/unsafe.json',
      ...valid.sublist(0, valid.length - 2),
      '--evidence',
      unsafeEvidence.path,
    ]);
    expect(result.exitCode, 64);
  });

  test('accepts inconclusive failure but refuses misleading pass/overwrite',
      () async {
    final evidence = File('${temp.path}/baseline.log')
      ..writeAsStringSync('log');
    final output = '${temp.path}/receipt.json';
    final args = [
      '--output',
      output,
      '--platform',
      'ios',
      '--selection',
      'ios-baseline',
      '--execution-class',
      'physical-device',
      '--status',
      'inconclusive',
      '--scenario',
      'KB-IOS-001=inconclusive',
      '--scenario',
      'KB-IOS-010=inconclusive',
      '--scenario',
      'KB-IOS-020=inconclusive',
      '--field',
      'osVersion=iOS 19',
      '--evidence',
      evidence.path,
    ];
    expect((await run(args)).exitCode, 0);
    expect((await run(args)).exitCode, 64);
    final misleading = [...args];
    misleading[misleading.indexOf('inconclusive')] = 'pass';
    misleading[1] = '${temp.path}/misleading.json';
    expect((await run(misleading)).exitCode, 64);

    final downgradedFailure = [
      '--output',
      '${temp.path}/downgraded.json',
      '--platform',
      'ios',
      '--selection',
      'ios-baseline',
      '--execution-class',
      'physical-device',
      '--status',
      'inconclusive',
      '--scenario',
      'KB-IOS-001=fail',
      '--scenario',
      'KB-IOS-010=inconclusive',
      '--scenario',
      'KB-IOS-020=pass',
      '--field',
      'osVersion=iOS 19',
      '--evidence',
      evidence.path,
    ];
    expect((await run(downgradedFailure)).exitCode, 64);
    downgradedFailure[downgradedFailure.indexOf('inconclusive')] = 'fail';
    downgradedFailure[1] = '${temp.path}/failed.json';
    expect((await run(downgradedFailure)).exitCode, 0);
  });

  test('rejects invented selections/scenarios and symlinked paths', () async {
    final evidence = File('${temp.path}/baseline.log')
      ..writeAsStringSync('log');
    final base = [
      '--output',
      '${temp.path}/receipt.json',
      '--platform',
      'ios',
      '--selection',
      'ios-baseline',
      '--execution-class',
      'physical-device',
      '--status',
      'pass',
      '--scenario',
      'KB-IOS-001=pass',
      '--scenario',
      'KB-IOS-010=pass',
      '--scenario',
      'KB-IOS-020=pass',
      '--field',
      'osVersion=iOS 19',
      '--evidence',
      evidence.path,
    ];
    final inventedSelection = [...base]..[base.indexOf('--selection') + 1] =
        'made-up';
    expect((await run(inventedSelection)).exitCode, 64);
    final inventedScenario = [...base]..[base.indexOf('KB-IOS-020=pass')] =
        'NOT-A-SCENARIO=pass';
    expect((await run(inventedScenario)).exitCode, 64);

    final victim = File('${temp.path}/victim')..writeAsStringSync('untouched');
    final outputLink = Link('${temp.path}/receipt.json')
      ..createSync(victim.path);
    expect((await run(base)).exitCode, 64);
    expect(victim.readAsStringSync(), 'untouched');
    outputLink.deleteSync();

    final evidenceLink = Link('${temp.path}/evidence.log')
      ..createSync(evidence.path);
    final linkedEvidence = [...base]..[base.indexOf(evidence.path)] =
        evidenceLink.path;
    expect((await run(linkedEvidence)).exitCode, 64);
  });

  test('physical iOS selector requires one exact connected non-emulator',
      () async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['$repo/tool/device_security/flutter_device.dart', 'physical-id'],
      workingDirectory: repo,
    );
    process.stdin.write(jsonEncode([
      {
        'id': 'physical-id',
        'targetPlatform': 'ios',
        'emulator': false,
        'isSupported': true,
        'sdk': 'iOS 19.0',
      },
      {
        'id': 'simulator-id',
        'targetPlatform': 'ios',
        'emulator': true,
        'isSupported': true,
        'sdk': 'iOS 19.0',
      },
    ]));
    await process.stdin.close();
    expect(await process.exitCode, 0);
    expect(await utf8.decoder.bind(process.stdout).join(), 'iOS 19.0\n');

    final rejected = await Process.start(
      Platform.resolvedExecutable,
      ['$repo/tool/device_security/flutter_device.dart', 'simulator-id'],
      workingDirectory: repo,
    );
    rejected.stdin.write(jsonEncode([
      {
        'id': 'simulator-id',
        'targetPlatform': 'ios',
        'emulator': true,
        'isSupported': true,
        'sdk': 'iOS 19.0',
      }
    ]));
    await rejected.stdin.close();
    expect(await rejected.exitCode, 65);

    for (final invalidDevice in [
      {
        'id': 'physical-id',
        'targetPlatform': 'ios-remote',
        'emulator': false,
        'isSupported': true,
        'sdk': 'iOS 19.0',
      },
      {
        'id': 'physical-id',
        'targetPlatform': 'ios',
        'emulator': false,
        'sdk': 'iOS 19.0',
      },
    ]) {
      final malformed = await Process.start(
        Platform.resolvedExecutable,
        ['$repo/tool/device_security/flutter_device.dart', 'physical-id'],
        workingDirectory: repo,
      );
      malformed.stdin.write(jsonEncode([invalidDevice]));
      await malformed.stdin.close();
      expect(await malformed.exitCode, 65);
    }
  });

  test('Android cleanup fails closed and Flutter runs stay user-scoped',
      () async {
    final adapter =
        File('$repo/tool/device_security/android.sh').readAsStringSync();
    expect(
      RegExp(r'--device-user "\$ANDROID_USER"').allMatches(adapter).length,
      2,
    );

    const harness = r'''
set -uo pipefail
REPO="$KEYBAY_TEST_REPO"
source "$REPO/tool/device_security/common.sh"
source "$REPO/tool/device_security/android.sh"
ANDROID_DEVICE=fake-device
ANDROID_USER=0

adb() {
  case "$KEYBAY_ADB_MODE:$*" in
    query-error:*"shell pm list packages"*) return 42 ;;
    other-user:*"shell pm list users"*)
      printf 'Users:\n  UserInfo{0:Owner:13} running\n  UserInfo{10:Work:30}\n'
      ;;
    other-user:*"shell pm list packages --user 10"*)
      printf 'package:dev.keybay.securityharness\n'
      ;;
    other-user:*"shell pm list packages --user 0"*) return 0 ;;
    *) return 42 ;;
  esac
}

if _android_cleanup_harness; then
  exit 1
fi
''';
    for (final mode in ['query-error', 'other-user']) {
      final result = await Process.run(
        'bash',
        ['-c', harness],
        workingDirectory: repo,
        environment: {
          ...Platform.environment,
          'KEYBAY_TEST_REPO': repo,
          'KEYBAY_ADB_MODE': mode,
        },
      );
      expect(result.exitCode, 0,
          reason: '$mode stdout=${result.stdout} stderr=${result.stderr}');
    }
  });

  test('entrypoint rejects platform traversal before sourcing', () async {
    final result = await Process.run(
      'bash',
      ['$repo/tool/device_security.sh', 'doctor', '../device_security/linux'],
      workingDirectory: repo,
    );
    expect(result.exitCode, 64);
    expect(result.stderr, contains('unsupported platform'));
  });

  test('Android harness backup policy excludes every Keybay file namespace',
      () {
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
      reason: 'cloud and device-transfer must both exclude all file stores',
    );
  });

  test('macOS e2e cleanup and entitlement follow the harness bundle ID', () {
    final config = File(
      '$repo/example_flutter/macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final bundleId = RegExp(
      r'^PRODUCT_BUNDLE_IDENTIFIER = (\S+)$',
      multiLine: true,
    ).firstMatch(config)?.group(1);
    expect(bundleId, isNotNull);

    final script = File('$repo/tool/test_e2e.sh').readAsStringSync();
    expect(script, contains('HARNESS_BUNDLE_ID="$bundleId"'));
    expect(
      script,
      contains(r'$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)'),
    );

    final recipe =
        File('$repo/tool/dp_keychain_verification.md').readAsStringSync();
    expect(
      recipe,
      contains(r'$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)'),
    );
  });
}
