import 'dart:convert';
import 'dart:io';

import '../device_security/catalog.dart';

final class ManifestException implements Exception {
  ManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> main(List<String> args) async {
  try {
    final parsed = _parse(args);
    final manifest = await _build(parsed);
    final output = File(parsed.output).absolute;
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ManifestException('output already exists');
    }
    await output.create(exclusive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
      flush: true,
    );
    stdout.writeln(output.path);
  } on Exception catch (error) {
    stderr.writeln('assurance-manifest: $error');
    exitCode = error is ManifestException ? 64 : 74;
  }
}

typedef _Config = ({
  String output,
  String subject,
  String version,
  String ciRunId,
  List<(String, String)> artifacts,
  List<String> receipts,
  List<String> requiredSelections,
  List<String> unqualified,
  List<String> limitations,
});

_Config _parse(List<String> args) {
  final single = <String, String>{};
  final artifacts = <(String, String)>[];
  final receipts = <String>[];
  final required = <String>[];
  final unqualified = <String>[];
  final limitations = <String>[];
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length || !args[index].startsWith('--')) {
      throw ManifestException('every option requires a value');
    }
    final option = args[index];
    final value = args[index + 1];
    switch (option) {
      case '--artifact':
        artifacts.add(_pair(value, option));
      case '--receipt':
        receipts.add(value);
      case '--require-selection':
        required.add(_name(value, 'selection'));
      case '--unqualified':
        unqualified.add(_text(value));
      case '--limitation':
        final uri = Uri.tryParse(value);
        if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
          throw ManifestException('limitations must be absolute HTTPS links');
        }
        limitations.add(value);
      case '--output' || '--subject' || '--version' || '--ci-run-id':
        if (single.containsKey(option)) {
          throw ManifestException('$option may be supplied only once');
        }
        single[option] = value;
      default:
        throw ManifestException('unknown option: $option');
    }
  }
  String requiredSingle(String option) =>
      single[option] ?? (throw ManifestException('missing required $option'));
  final subject = requiredSingle('--subject');
  if (!const {'core', 'cli'}.contains(subject)) {
    throw ManifestException('subject must be core or cli');
  }
  final version = requiredSingle('--version');
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    throw ManifestException('version must be stable semver');
  }
  final ciRunId = requiredSingle('--ci-run-id');
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(ciRunId)) {
    throw ManifestException('CI run ID must be a positive integer');
  }
  if (artifacts.isEmpty) {
    throw ManifestException('at least one artifact is required');
  }
  if (subject == 'core' && artifacts.length != 1) {
    throw ManifestException('core manifest requires one pub archive');
  }
  if (subject == 'cli' && receipts.isNotEmpty) {
    throw ManifestException('CLI releases do not consume device receipts');
  }
  return (
    output: requiredSingle('--output'),
    subject: subject,
    version: version,
    ciRunId: ciRunId,
    artifacts: artifacts,
    receipts: receipts,
    requiredSelections: required,
    unqualified: unqualified,
    limitations: limitations,
  );
}

Future<Map<String, Object?>> _build(_Config config) async {
  final repo = File.fromUri(Platform.script).parent.parent.parent.absolute;
  final git = _firstExisting(['/usr/bin/git', '/bin/git']);
  final commit = await _run(git, ['-C', repo.path, 'rev-parse', 'HEAD']);
  if ((await _run(git, [
    '-C',
    repo.path,
    'status',
    '--porcelain',
    '--untracked-files=all',
  ]))
      .isNotEmpty) {
    throw ManifestException('manifest generation requires a clean checkout');
  }

  final artifacts = <Map<String, Object>>[];
  String? coreDigest;
  final names = <String>{};
  for (final (name, rawPath) in config.artifacts) {
    if (!names.add(_name(name, 'artifact name'))) {
      throw ManifestException('duplicate artifact name: $name');
    }
    final file = File(rawPath).absolute;
    _regular(file, 'artifact');
    final digest = config.subject == 'core'
        ? await _canonicalPubDigest(repo, file)
        : await _sha256(file);
    if (config.subject == 'core') coreDigest = digest;
    artifacts.add({
      'name': name,
      'identity': config.subject == 'core'
          ? 'canonical-package-content-sha256'
          : 'file-sha256',
      'sha256': digest,
      if (config.subject == 'cli') 'bytes': file.lengthSync(),
    });
  }

  final receiptRecords = <Map<String, Object?>>[];
  final observedSelections = <String>{};
  for (final rawPath in config.receipts) {
    final receiptFile = File(rawPath).absolute;
    _regular(receiptFile, 'receipt');
    final Object? decoded;
    try {
      decoded = jsonDecode(await receiptFile.readAsString());
    } on FormatException {
      throw ManifestException('receipt contains malformed JSON');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['schema'] != 'keybay.device-security-receipt' ||
        decoded['schema_version'] != 2 ||
        decoded['status'] != 'pass') {
      throw ManifestException('receipt is not a passing release receipt');
    }
    final subject = decoded['subject'];
    if (subject is! Map<String, dynamic> ||
        subject['sha256'] != coreDigest ||
        subject['kind'] != 'core-pub-content-sha256') {
      throw ManifestException('receipt belongs to a different core subject');
    }
    final (selection, platform, executionClass, receiptSuiteCommit) =
        _validatePassingReceipt(decoded);
    await _validateSuiteApplicability(
      git,
      repo,
      receiptSuiteCommit,
      commit,
    );
    if (!observedSelections.add(selection)) {
      throw ManifestException('duplicate receipt selection: $selection');
    }
    final evidence = decoded['evidence'];
    if (evidence is! List || evidence.isEmpty) {
      throw ManifestException('receipt has no retained evidence');
    }
    final retained = <Map<String, Object>>[];
    for (final entry in evidence) {
      if (entry is! Map<String, dynamic> ||
          entry['path'] is! String ||
          entry['sha256'] is! String) {
        throw ManifestException('receipt evidence record was malformed');
      }
      final name = entry['path'] as String;
      if (name != Uri(path: name).pathSegments.single) {
        throw ManifestException('receipt evidence path was unsafe');
      }
      final file = File('${receiptFile.parent.path}/$name');
      _regular(file, 'retained evidence');
      final digest = await _sha256(file);
      if (digest != entry['sha256']) {
        throw ManifestException('retained evidence digest mismatch');
      }
      if (entry['bytes'] is! int || entry['bytes'] != file.lengthSync()) {
        throw ManifestException('retained evidence length mismatch');
      }
      retained.add({'path': name, 'sha256': digest});
    }
    receiptRecords.add({
      'path': receiptFile.uri.pathSegments.last,
      'sha256': await _sha256(receiptFile),
      'platform': platform,
      'selection': selection,
      'execution_class': executionClass,
      'evidence': retained,
    });
  }
  final missing = config.requiredSelections
      .where((selection) => !observedSelections.contains(selection))
      .toList();
  if (missing.isNotEmpty) {
    throw ManifestException(
        'missing required qualification receipts: ${missing.join(', ')}');
  }

  return {
    'schema': 'keybay.release-assurance-manifest',
    'schema_version': 1,
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'subject': config.subject == 'core' ? 'keybay-core' : 'keybay-cli',
    'version': config.version,
    'source': {'repository': 'danReynolds/keybay', 'commit': commit},
    'ci': {
      'repository': 'danReynolds/keybay',
      'run_id': config.ciRunId,
      'workflow': config.subject == 'core' ? 'publish.yml' : 'release_cli.yml',
    },
    'artifacts': artifacts,
    'qualification_receipts': receiptRecords,
    'temporary_exceptions': const [],
    'unqualified_configurations': config.unqualified,
    'canonical_limitations': config.limitations,
  };
}

(String, String, String, String) _validatePassingReceipt(
  Map<String, dynamic> receipt,
) {
  final selection = receipt['selection'];
  final platform = receipt['platform'];
  final executionClass = receipt['execution_class'];
  if (selection is! String ||
      platform is! String ||
      executionClass is! String) {
    throw ManifestException('receipt selection metadata was invalid');
  }
  final List<SecurityScenario> selected;
  try {
    selected = scenariosForSelection(selection);
  } on ArgumentError {
    throw ManifestException('receipt names an unknown executable selection');
  }
  if (selected.any((scenario) => scenario.platform.name != platform)) {
    throw ManifestException('receipt selection/platform mismatch');
  }
  final requiredExecution =
      platform == 'macos' ? 'native-host' : 'physical-device';
  if (executionClass != requiredExecution) {
    throw ManifestException('receipt execution class was invalid');
  }

  final timestamp = receipt['timestamp'];
  final suite = receipt['suite'];
  final nonce = receipt['run_nonce'];
  final installer = receipt['installer'];
  final cleanup = receipt['cleanup'];
  if (timestamp is! String ||
      DateTime.tryParse(timestamp)?.isUtc != true ||
      suite is! Map<String, dynamic> ||
      suite['clean'] != true ||
      suite['commit'] is! String ||
      !RegExp(r'^[0-9a-f]{40}$').hasMatch(suite['commit'] as String) ||
      nonce is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce) ||
      installer is! Map<String, dynamic> ||
      installer['status'] != 'pass' ||
      installer['package_id'] != 'dev.keybay.securityharness' ||
      installer['sha256'] is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(installer['sha256'] as String) ||
      cleanup is! Map<String, dynamic> ||
      cleanup['status'] != 'pass') {
    throw ManifestException('receipt release-binding metadata was invalid');
  }

  final scenarios = receipt['scenarios'];
  if (scenarios is! List) {
    throw ManifestException('receipt omitted scenario outcomes');
  }
  final expectedIds = selected.map((scenario) => scenario.id).toSet();
  final observedIds = <String>{};
  for (final outcome in scenarios) {
    if (outcome is! Map<String, dynamic> ||
        outcome['id'] is! String ||
        outcome['status'] != 'pass' ||
        !expectedIds.contains(outcome['id']) ||
        !observedIds.add(outcome['id'] as String)) {
      throw ManifestException('receipt scenario outcomes were invalid');
    }
  }
  if (observedIds.length != expectedIds.length ||
      !observedIds.containsAll(expectedIds)) {
    throw ManifestException('receipt omitted a required passing scenario');
  }
  return (
    selection,
    platform,
    executionClass,
    suite['commit'] as String,
  );
}

Future<void> _validateSuiteApplicability(
  String git,
  Directory repo,
  String receiptCommit,
  String releaseCommit,
) async {
  await _run(git, [
    '-C',
    repo.path,
    'cat-file',
    '-e',
    '$receiptCommit^{commit}',
  ]);
  await _run(git, [
    '-C',
    repo.path,
    'merge-base',
    '--is-ancestor',
    receiptCommit,
    releaseCommit,
  ]);
  final changed = await _run(git, [
    '-C',
    repo.path,
    'diff',
    '--name-only',
    '$receiptCommit..$releaseCommit',
  ]);
  final invalidating = changed
      .split('\n')
      .where((path) =>
          path.isNotEmpty && !path.startsWith('doc/device-security-receipts/'))
      .toList();
  if (invalidating.isNotEmpty) {
    throw ManifestException(
      'receipt predates release-affecting changes: ${invalidating.join(', ')}',
    );
  }
}

Future<String> _canonicalPubDigest(Directory repo, File archive) async {
  final python =
      _firstExisting(['/usr/bin/python3', '/opt/homebrew/bin/python3']);
  final digest = await _run(python, [
    '${repo.path}/tool/compare_pub_archives.py',
    '--digest',
    archive.path,
  ]);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw ManifestException('canonical package digest was malformed');
  }
  return digest;
}

Future<String> _sha256(File file) async {
  for (final (command, arguments) in <(String, List<String>)>[
    ('/usr/bin/shasum', ['-a', '256', '--', file.path]),
    ('/usr/bin/sha256sum', ['--', file.path]),
    ('/bin/sha256sum', ['--', file.path]),
  ]) {
    if (!File(command).existsSync()) continue;
    final output = await _run(command, arguments);
    final digest = output.split(RegExp(r'\s+')).first;
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return digest;
  }
  throw ManifestException('no SHA-256 implementation is available');
}

void _regular(File file, String label) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ManifestException('$label must be a regular file');
  }
}

Future<String> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ManifestException('$executable exited ${result.exitCode}');
  }
  return (result.stdout as String).trim();
}

String _firstExisting(List<String> paths) {
  for (final path in paths) {
    if (File(path).existsSync()) return path;
  }
  throw ManifestException('required system executable is unavailable');
}

(String, String) _pair(String value, String option) {
  final index = value.indexOf('=');
  if (index < 1 || index == value.length - 1) {
    throw ManifestException('$option requires NAME=PATH');
  }
  return (value.substring(0, index), value.substring(index + 1));
}

String _name(String value, String label) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value)) {
    throw ManifestException('invalid $label: $value');
  }
  return value;
}

String _text(String value) {
  final result = value.trim();
  if (result.isEmpty ||
      result.length > 512 ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(result)) {
    throw ManifestException('manifest text was unsafe');
  }
  return result;
}
