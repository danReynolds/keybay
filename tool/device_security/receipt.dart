import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'catalog.dart';

const _platforms = {'android', 'ios', 'macos', 'linux'};
const _statuses = {'pass', 'fail', 'blocked', 'skipped', 'inconclusive'};
const _executionClasses = {
  'hermetic',
  'native-host',
  'virtual-device',
  'physical-device',
};
const _knownFieldNames =
    'suite_version model os_version api_level security_patch '
    'build_fingerprint verified_boot selinux fbe architecture '
    'storage_scheme signing_identity protection_level';
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

typedef _Scenario = ({String id, String status});
typedef _NativeLink = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _DartLink = int Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _NativeMalloc = Pointer<Void> Function(IntPtr);
typedef _DartMalloc = Pointer<Void> Function(int);
typedef _NativeFree = Void Function(Pointer<Void>);
typedef _DartFree = void Function(Pointer<Void>);
typedef _Config = ({
  String output,
  String platform,
  String selection,
  String executionClass,
  String status,
  List<_Scenario> scenarios,
  Map<String, String> fields,
  List<String> evidence,
});

final class ReceiptException implements Exception {
  ReceiptException(this.message);
  final String message;

  @override
  String toString() => message;
}

Future<void> main(List<String> args) async {
  try {
    final config = _parse(args);
    final receipt = await _buildReceipt(config);
    final output = await _writeReceipt(receipt, config.output);
    stdout.writeln(output.path);
  } on Exception catch (error) {
    stderr.writeln('receipt: $error');
    exitCode = error is ReceiptException ? 64 : 74;
  }
}

_Config _parse(List<String> args) {
  final single = <String, String>{};
  final scenarios = <_Scenario>[];
  final fields = <String, String>{};
  final evidence = <String>[];
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length || !args[i].startsWith('--')) {
      throw ReceiptException('every option requires a value');
    }
    final option = args[i];
    final value = args[i + 1];
    switch (option) {
      case '--output' ||
            '--platform' ||
            '--selection' ||
            '--execution-class' ||
            '--status':
        if (single.containsKey(option)) {
          throw ReceiptException('$option may be supplied only once');
        }
        single[option] = value;
      case '--scenario':
        final pair = _pair(value, option);
        scenarios
            .add((id: _name(pair.$1, 'scenario ID'), status: _status(pair.$2)));
      case '--field':
        final pair = _pair(value, option);
        final key = _fieldKey(pair.$1);
        if (RegExp(r'(^|_)(serial|udid|identifier|device_id)($|_)')
            .hasMatch(key)) {
          throw ReceiptException('raw device identifiers are not accepted');
        }
        if (!_knownFieldNames.split(' ').contains(key)) {
          throw ReceiptException('unknown receipt field: $key');
        }
        if (fields.containsKey(key)) {
          throw ReceiptException('duplicate receipt field: $key');
        }
        fields[key] = _text(pair.$2);
      case '--evidence':
        evidence.add(value);
      default:
        throw ReceiptException('unknown option: $option');
    }
  }

  String required(String option) =>
      single[option] ?? (throw ReceiptException('missing required $option'));
  final platform = required('--platform').toLowerCase();
  if (!_platforms.contains(platform)) {
    throw ReceiptException('unsupported platform: $platform');
  }
  final status = _status(required('--status'));
  final selection = _name(required('--selection'), 'selection').toLowerCase();
  final executionClass = required('--execution-class').toLowerCase();
  if (!_executionClasses.contains(executionClass)) {
    throw ReceiptException('invalid execution class: $executionClass');
  }
  final List<SecurityScenario> selected;
  try {
    selected = scenariosForSelection(selection);
  } on ArgumentError {
    throw ReceiptException('unknown executable selection: $selection');
  }
  if (selected.any((scenario) => scenario.platform.name != platform)) {
    throw ReceiptException('selection $selection does not belong to $platform');
  }
  final expectedScenarios = selected.map((scenario) => scenario.id).toSet();
  final requiredExecution = switch (platform) {
    'android' || 'ios' => 'physical-device',
    'macos' => 'native-host',
    _ => null,
  };
  if (requiredExecution != null && executionClass != requiredExecution) {
    throw ReceiptException(
        '$platform/$selection requires execution class $requiredExecution');
  }
  if (scenarios.isEmpty) {
    throw ReceiptException('at least one --scenario is required');
  }
  final ids = <String>{};
  for (final scenario in scenarios) {
    if (!ids.add(scenario.id)) {
      throw ReceiptException('duplicate scenario ID: ${scenario.id}');
    }
  }
  if (!ids.containsAll(expectedScenarios) ||
      !expectedScenarios.containsAll(ids)) {
    throw ReceiptException(
        '$platform/$selection requires scenarios ${expectedScenarios.join(', ')}');
  }
  final missingFields = _requiredFields[platform]!
      .where((field) => !fields.containsKey(field))
      .toList();
  if (missingFields.isNotEmpty) {
    throw ReceiptException(
        '$platform receipt is missing fields: ${missingFields.join(', ')}');
  }
  if (evidence.isEmpty) {
    throw ReceiptException('at least one --evidence file is required');
  }
  if (evidence.length > 8) {
    throw ReceiptException('at most eight --evidence files are accepted');
  }
  if (status == 'pass' && scenarios.any((item) => item.status != 'pass')) {
    throw ReceiptException('overall pass requires every scenario to pass');
  }
  if (status != 'fail' && scenarios.any((item) => item.status == 'fail')) {
    throw ReceiptException('a failed scenario requires overall fail');
  }
  if (status != 'pass' && scenarios.every((item) => item.status != status)) {
    throw ReceiptException(
        'overall $status requires at least one $status scenario');
  }
  return (
    output: required('--output'),
    platform: platform,
    selection: selection,
    executionClass: executionClass,
    status: status,
    scenarios: scenarios,
    fields: fields,
    evidence: evidence,
  );
}

Future<Map<String, Object?>> _buildReceipt(_Config config) async {
  final git = _firstExisting(['/usr/bin/git', '/bin/git']);
  final commit = await _run(git, ['rev-parse', 'HEAD'], cleanGitEnv: true);
  final dirty = (await _run(git, ['status', '--porcelain'], cleanGitEnv: true))
      .isNotEmpty;
  final fields = config.fields;
  final api =
      fields['api_level'] == null ? null : int.tryParse(fields['api_level']!);
  if (fields['api_level'] != null && api == null) {
    throw ReceiptException('apiLevel must be an integer');
  }
  final patch = fields['security_patch'];
  if (patch != null && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(patch)) {
    throw ReceiptException('securityPatch must use YYYY-MM-DD');
  }
  final output = File(config.output).absolute;
  final parentType = await FileSystemEntity.type(
    output.parent.path,
    followLinks: false,
  );
  if (parentType != FileSystemEntityType.directory) {
    throw ReceiptException('receipt parent must be a real directory');
  }
  final parentStat = await output.parent.stat();
  if ((parentStat.mode & 0x3f) != 0) {
    throw ReceiptException('receipt parent must not grant group/other access');
  }

  final evidence = <Map<String, Object>>[];
  final names = <String>{};
  for (final path in config.evidence) {
    final file = File(path).absolute;
    if (file.parent.path != output.parent.path) {
      throw ReceiptException(
          'evidence must be a direct child of the receipt directory');
    }
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw ReceiptException('evidence is not a regular file: $path');
    }
    final before = await file.stat();
    if (before.size > 16 * 1024 * 1024) {
      throw ReceiptException('evidence exceeds the 16 MiB cap: $path');
    }
    final name = file.uri.pathSegments.last;
    if (!RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(name) ||
        RegExp(r'serial|udid|secret|token|password', caseSensitive: false)
            .hasMatch(name)) {
      throw ReceiptException('unsafe evidence filename: $name');
    }
    if (!names.add(name)) {
      throw ReceiptException('duplicate evidence filename: $name');
    }
    final digest = await _sha256(file);
    final after = await file.stat();
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw ReceiptException('evidence changed while hashing: $path');
    }
    evidence.add({
      'path': name,
      'sha256': digest,
      'bytes': before.size,
    });
  }
  return {
    'schema': 'keybay.device-security-receipt',
    'schema_version': 1,
    'suite_version': fields['suite_version'] ?? '1',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'repository': {'commit': commit, 'dirty': dirty},
    'platform': config.platform,
    'selection': config.selection,
    'execution_class': config.executionClass,
    'status': config.status,
    'device': {
      'model': fields['model'],
      'build': fields['build_fingerprint'],
      'api_level': api,
      'security_patch': patch,
    },
    'scenarios': [
      for (final item in config.scenarios)
        {'id': item.id, 'status': item.status}
    ],
    'evidence': evidence,
    'fields': {
      for (final key in [
        'os_version',
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
  };
}

Future<String> _sha256(File file) async {
  for (final command in <(String, List<String>)>[
    ('/usr/bin/shasum', ['-a', '256', '--', file.path]),
    ('/usr/bin/sha256sum', ['--', file.path]),
    ('/bin/sha256sum', ['--', file.path]),
  ]) {
    if (!File(command.$1).existsSync()) continue;
    try {
      final output = await _run(command.$1, command.$2);
      final digest = output.split(RegExp(r'\s+')).first.toLowerCase();
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return digest;
    } catch (_) {
      continue;
    }
  }
  throw ReceiptException(
      'neither shasum nor sha256sum could hash ${file.path}');
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
    throw ReceiptException('$command exited ${result.exitCode}');
  }
  return (result.stdout as String).trim();
}

Future<File> _writeReceipt(Map<String, Object?> receipt, String path) async {
  final output = File(path).absolute;
  if (await FileSystemEntity.type(output.path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw ReceiptException('output already exists');
  }
  final random = Random.secure();
  final token = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temp = File('${output.path}.tmp.$token');
  try {
    await temp.create(exclusive: true);
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
      flush: true,
    );
    if (!_linkNoReplace(temp.path, output.path)) {
      if (await FileSystemEntity.type(output.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw ReceiptException('output already exists');
      }
      throw ReceiptException('failed to publish receipt atomically');
    }
    return output;
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

bool _linkNoReplace(String source, String destination) {
  final library = DynamicLibrary.process();
  final link = library.lookupFunction<_NativeLink, _DartLink>('link');
  final malloc = library.lookupFunction<_NativeMalloc, _DartMalloc>('malloc');
  final free = library.lookupFunction<_NativeFree, _DartFree>('free');
  final sourcePointer = _nativeUtf8(source, malloc);
  var destinationPointer = nullptr.cast<Uint8>();
  try {
    destinationPointer = _nativeUtf8(destination, malloc);
    return link(sourcePointer, destinationPointer) == 0;
  } finally {
    free(sourcePointer.cast());
    if (destinationPointer != nullptr) free(destinationPointer.cast());
  }
}

Pointer<Uint8> _nativeUtf8(String value, _DartMalloc malloc) {
  final bytes = utf8.encode(value);
  final pointer = malloc(bytes.length + 1).cast<Uint8>();
  if (pointer == nullptr) {
    throw ReceiptException('could not allocate a native path');
  }
  final buffer = pointer.asTypedList(bytes.length + 1);
  buffer.setRange(0, bytes.length, bytes);
  buffer[bytes.length] = 0;
  return pointer;
}

String _firstExisting(List<String> candidates) {
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  throw ReceiptException('required system command is unavailable');
}

(String, String) _pair(String value, String option) {
  final at = value.indexOf('=');
  if (at < 1 || at == value.length - 1) {
    throw ReceiptException('$option requires KEY=VALUE');
  }
  return (value.substring(0, at), value.substring(at + 1));
}

String _status(String value) {
  final result = value.trim().toLowerCase();
  if (!_statuses.contains(result)) {
    throw ReceiptException('invalid status: $value');
  }
  return result;
}

String _name(String value, String label) {
  final result = value.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(result)) {
    throw ReceiptException('invalid $label: $value');
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
    throw ReceiptException('receipt field contains unsafe text');
  }
  return result;
}
