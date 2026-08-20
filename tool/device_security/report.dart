import 'dart:convert';
import 'dart:io';

import 'catalog.dart';

const _platforms = {'android', 'ios', 'macos'};
const _executionClasses = {'native-host', 'physical-device'};
const _knownFieldNames =
    'model os_version api_level security_patch build_fingerprint '
    'verified_boot selinux fbe architecture storage_scheme signing_identity '
    'protection_level';
const _requiredFields = <String, Set<String>>{
  'android': {
    'model',
    'os_version',
    'api_level',
    'security_patch',
    'build_fingerprint',
    'verified_boot',
    'selinux',
    'fbe',
  },
  'ios': {'os_version'},
  'macos': {
    'model',
    'os_version',
    'architecture',
    'storage_scheme',
    'signing_identity',
    'protection_level',
  },
};

typedef _Config = ({
  String output,
  String platform,
  String selection,
  String executionClass,
  String nonce,
  String results,
  String commandStatus,
  String cleanupStatus,
  Map<String, String> fields,
  List<String> limitations,
});

final class ReportException implements Exception {
  ReportException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> main(List<String> args) async {
  try {
    final config = _parse(args);
    final report = await _buildReport(config);
    final output = await _writeReport(report, config.output);
    stdout.writeln(output.path);
  } on Exception catch (error) {
    stderr.writeln('device-security-report: $error');
    exitCode = error is ReportException ? 64 : 74;
  }
}

_Config _parse(List<String> args) {
  final single = <String, String>{};
  final fields = <String, String>{};
  final limitations = <String>[];
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length || !args[index].startsWith('--')) {
      throw ReportException('every option requires a value');
    }
    final option = args[index];
    final value = args[index + 1];
    if (option == '--field') {
      final pair = _pair(value, option);
      final key = _fieldKey(pair.$1);
      if (RegExp(r'(^|_)(serial|udid|identifier|device_id)($|_)')
          .hasMatch(key)) {
        throw ReportException('raw device identifiers are not accepted');
      }
      if (!_knownFieldNames.split(' ').contains(key)) {
        throw ReportException('unknown report field: $key');
      }
      if (fields.containsKey(key)) {
        throw ReportException('duplicate report field: $key');
      }
      fields[key] = _text(pair.$2);
      continue;
    }
    if (option == '--limitation') {
      limitations.add(_text(value));
      continue;
    }
    if (!const {
      '--output',
      '--platform',
      '--selection',
      '--execution-class',
      '--nonce',
      '--results',
      '--command-status',
      '--cleanup-status',
    }.contains(option)) {
      throw ReportException('unknown option: $option');
    }
    if (single.containsKey(option)) {
      throw ReportException('$option may be supplied only once');
    }
    single[option] = value;
  }

  String required(String option) =>
      single[option] ?? (throw ReportException('missing required $option'));
  final platform = required('--platform').toLowerCase();
  if (!_platforms.contains(platform)) {
    throw ReportException('unsupported platform: $platform');
  }
  final selection = _name(required('--selection'), 'selection').toLowerCase();
  final executionClass = required('--execution-class').toLowerCase();
  if (!_executionClasses.contains(executionClass)) {
    throw ReportException('invalid execution class: $executionClass');
  }
  final List<SecurityScenario> selected;
  try {
    selected = scenariosForSelection(selection);
  } on ArgumentError {
    throw ReportException('unknown executable selection: $selection');
  }
  if (selected.any((scenario) => scenario.platform.name != platform)) {
    throw ReportException('selection $selection does not belong to $platform');
  }
  final requiredExecution =
      platform == 'macos' ? 'native-host' : 'physical-device';
  if (executionClass != requiredExecution) {
    throw ReportException(
      '$platform/$selection requires execution class $requiredExecution',
    );
  }
  final missingFields = _requiredFields[platform]!
      .where((field) => !fields.containsKey(field))
      .toList();
  if (missingFields.isNotEmpty) {
    throw ReportException(
      '$platform report is missing fields: ${missingFields.join(', ')}',
    );
  }
  final nonce = required('--nonce');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce)) {
    throw ReportException('nonce must be 64 lowercase hexadecimal digits');
  }
  final commandStatus = required('--command-status');
  if (!const {'pass', 'fail'}.contains(commandStatus)) {
    throw ReportException('command status must be pass or fail');
  }
  final cleanupStatus = required('--cleanup-status');
  if (!const {'pass', 'fail', 'not-required'}.contains(cleanupStatus)) {
    throw ReportException('cleanup status must be pass, fail, or not-required');
  }
  if (limitations.isEmpty) {
    throw ReportException('at least one limitation is required');
  }
  return (
    output: required('--output'),
    platform: platform,
    selection: selection,
    executionClass: executionClass,
    nonce: nonce,
    results: required('--results'),
    commandStatus: commandStatus,
    cleanupStatus: cleanupStatus,
    fields: fields,
    limitations: limitations,
  );
}

Future<Map<String, Object?>> _buildReport(_Config config) async {
  final repo = File.fromUri(Platform.script).parent.parent.parent.absolute;
  final git = _firstExisting(['/usr/bin/git', '/bin/git']);
  final commit = await _run(
    git,
    ['-C', repo.path, 'rev-parse', 'HEAD'],
    cleanGitEnv: true,
  );
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
    throw ReportException('source commit was malformed');
  }
  final dirty = (await _run(
    git,
    ['-C', repo.path, 'status', '--porcelain', '--untracked-files=all'],
    cleanGitEnv: true,
  ))
      .isNotEmpty;
  if (dirty) {
    throw ReportException('reports require a clean source checkout');
  }

  final output = File(config.output).absolute;
  await _requirePrivateParent(output);
  final resultsFile = File(config.results).absolute;
  _requireRegularFile(resultsFile, 'structured results');
  final resultBytes = await resultsFile.readAsBytes();
  if (resultBytes.length > 1024 * 1024) {
    throw ReportException('structured results exceed the 1 MiB cap');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(resultBytes));
  } on FormatException {
    throw ReportException('structured results contain malformed JSON');
  }
  final sourceIdentity = 'git-commit:$commit';
  if (decoded is! Map<String, dynamic> ||
      decoded['schema'] != 'keybay.device-security-results' ||
      decoded['schema_version'] != 2 ||
      decoded['nonce'] != config.nonce ||
      decoded['subject'] != sourceIdentity ||
      decoded['selection'] != config.selection ||
      decoded['command_status'] != config.commandStatus) {
    throw ReportException('structured results do not match this run/source');
  }

  final selected = scenariosForSelection(config.selection);
  final expectedTestIds = selected
      .where((scenario) => !scenario.id.endsWith('-001'))
      .map((scenario) => scenario.id)
      .toSet();
  final resultStatuses = <String, ({String status, String reason})>{};
  final resultList = decoded['scenarios'];
  if (resultList is! List) {
    throw ReportException('structured results omitted scenarios');
  }
  for (final entry in resultList) {
    if (entry is! Map<String, dynamic> ||
        entry['id'] is! String ||
        entry['status'] is! String ||
        entry['reason'] is! String) {
      throw ReportException('structured scenario result was malformed');
    }
    final id = entry['id'] as String;
    final status = entry['status'] as String;
    if (!expectedTestIds.contains(id) ||
        !const {'pass', 'fail', 'blocked', 'skipped', 'inconclusive'}
            .contains(status) ||
        resultStatuses.containsKey(id)) {
      throw ReportException('unexpected or duplicate scenario result: $id');
    }
    resultStatuses[id] = (
      status: status,
      reason: _text(entry['reason'] as String),
    );
  }
  if (resultStatuses.length != expectedTestIds.length ||
      !resultStatuses.keys.toSet().containsAll(expectedTestIds)) {
    throw ReportException('structured results omitted a required scenario');
  }

  final inventoryStatus = _inventoryStatus(config.platform, config.fields);
  final scenarios = <Map<String, String>>[
    for (final scenario in selected)
      if (scenario.id.endsWith('-001'))
        {
          'id': scenario.id,
          'status': inventoryStatus,
          'reason': 'validated by the platform adapter inventory',
        }
      else
        {
          'id': scenario.id,
          'status': resultStatuses[scenario.id]!.status,
          'reason': resultStatuses[scenario.id]!.reason,
        },
  ];
  final statuses = scenarios.map((scenario) => scenario['status']!).toList();
  final status = statuses.contains('fail')
      ? 'fail'
      : config.commandStatus == 'fail' || config.cleanupStatus == 'fail'
          ? 'inconclusive'
          : statuses.every((value) => value == 'pass')
              ? 'pass'
              : statuses.contains('inconclusive') ||
                      statuses.contains('skipped')
                  ? 'inconclusive'
                  : 'blocked';

  final fields = config.fields;
  final api =
      fields['api_level'] == null ? null : int.tryParse(fields['api_level']!);
  if (fields['api_level'] != null && api == null) {
    throw ReportException('apiLevel must be an integer');
  }
  final patch = fields['security_patch'];
  if (patch != null && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(patch)) {
    throw ReportException('securityPatch must use YYYY-MM-DD');
  }

  return {
    'schema': 'keybay.device-security-report',
    'schema_version': 1,
    'recorded_at': DateTime.now().toUtc().toIso8601String(),
    'source': {'commit': commit, 'clean': true},
    'platform': config.platform,
    'selection': config.selection,
    'execution_class': config.executionClass,
    'status': status,
    'configuration': {
      'model': fields['model'],
      'os_version': fields['os_version'],
      'build': fields['build_fingerprint'],
      'api_level': api,
      'security_patch': patch,
      for (final key in [
        'verified_boot',
        'selinux',
        'fbe',
        'architecture',
        'storage_scheme',
        'signing_identity',
        'protection_level',
      ])
        if (fields[key] != null) key: fields[key]!,
    },
    'command': {'status': config.commandStatus},
    'cleanup': {'status': config.cleanupStatus},
    'scenarios': scenarios,
    'limitations': config.limitations,
  };
}

String _inventoryStatus(String platform, Map<String, String> fields) {
  if (platform == 'android') {
    final api = int.tryParse(fields['api_level'] ?? '');
    final boot = fields['verified_boot'] ?? '';
    return api != null &&
            api >= 31 &&
            boot.contains('green') &&
            boot.contains('vbmeta=locked') &&
            boot.contains('flash-locked=1') &&
            fields['selinux'] == 'Enforcing' &&
            (fields['fbe'] ?? '').isNotEmpty &&
            fields['fbe'] != 'unreported'
        ? 'pass'
        : 'fail';
  }
  if (platform == 'macos') {
    return fields['architecture'] == 'arm64' &&
            fields['storage_scheme'] == 'encryptedFile' &&
            fields['signing_identity'] == 'ad-hoc' &&
            fields['protection_level'] == 'loginBound'
        ? 'pass'
        : 'fail';
  }
  return 'pass';
}

Future<void> _requirePrivateParent(File output) async {
  final parentType = await FileSystemEntity.type(
    output.parent.path,
    followLinks: false,
  );
  if (parentType != FileSystemEntityType.directory) {
    throw ReportException('report parent must be a real directory');
  }
  final parentStat = await output.parent.stat();
  if ((parentStat.mode & 0x3f) != 0) {
    throw ReportException('report parent must not grant group/other access');
  }
}

void _requireRegularFile(File file, String label) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ReportException('$label must be a regular file');
  }
}

Future<String> _run(
  String command,
  List<String> args, {
  bool cleanGitEnv = false,
}) async {
  final environment = Map<String, String>.of(Platform.environment);
  if (cleanGitEnv) {
    environment.removeWhere((key, _) => key.startsWith('GIT_'));
  }
  final result = await Process.run(
    command,
    args,
    environment: environment,
    includeParentEnvironment: false,
  );
  if (result.exitCode != 0) {
    throw ReportException('$command exited ${result.exitCode}');
  }
  return (result.stdout as String).trim();
}

Future<File> _writeReport(Map<String, Object?> report, String path) async {
  final output = File(path).absolute;
  if (await FileSystemEntity.type(output.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw ReportException('output already exists');
  }
  await output.create(exclusive: true);
  try {
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    return output;
  } on Object {
    if (await output.exists()) await output.delete();
    rethrow;
  }
}

String _firstExisting(List<String> candidates) {
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw ReportException('required system command is unavailable');
}

(String, String) _pair(String value, String option) {
  final at = value.indexOf('=');
  if (at < 1 || at == value.length - 1) {
    throw ReportException('$option requires KEY=VALUE');
  }
  return (value.substring(0, at), value.substring(at + 1));
}

String _name(String value, String label) {
  final result = value.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(result)) {
    throw ReportException('invalid $label: $value');
  }
  return result;
}

String _fieldKey(String value) => value
    .trim()
    .replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    )
    .toLowerCase()
    .replaceAll('-', '_')
    .replaceAll('.', '_');

String _text(String value) {
  final result = value.trim();
  if (result.isEmpty ||
      result.length > 512 ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(result)) {
    throw ReportException('report text contains unsafe content');
  }
  return result;
}
