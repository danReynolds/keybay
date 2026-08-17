import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'catalog.dart';

const _platforms = {'android', 'ios', 'macos'};
const _executionClasses = {
  'native-host',
  'physical-device',
};
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
  String nonce,
  String subjectArchive,
  String results,
  String cleanupStatus,
  String installerKind,
  String installerPath,
  String packageId,
  String installCommand,
  String installStatus,
  Map<String, String> fields,
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
  final fields = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length || !args[index].startsWith('--')) {
      throw ReceiptException('every option requires a value');
    }
    final option = args[index];
    final value = args[index + 1];
    if (option == '--field') {
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
      continue;
    }
    if (!const {
      '--output',
      '--platform',
      '--selection',
      '--execution-class',
      '--nonce',
      '--subject-archive',
      '--results',
      '--cleanup-status',
      '--installer-kind',
      '--installer-path',
      '--package-id',
      '--install-command',
      '--install-status',
    }.contains(option)) {
      throw ReceiptException('unknown option: $option');
    }
    if (single.containsKey(option)) {
      throw ReceiptException('$option may be supplied only once');
    }
    single[option] = value;
  }

  String required(String option) =>
      single[option] ?? (throw ReceiptException('missing required $option'));
  final platform = required('--platform').toLowerCase();
  if (!_platforms.contains(platform)) {
    throw ReceiptException('unsupported platform: $platform');
  }
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
  final requiredExecution =
      platform == 'macos' ? 'native-host' : 'physical-device';
  if (executionClass != requiredExecution) {
    throw ReceiptException(
        '$platform/$selection requires execution class $requiredExecution');
  }
  final missingFields = _requiredFields[platform]!
      .where((field) => !fields.containsKey(field))
      .toList();
  if (missingFields.isNotEmpty) {
    throw ReceiptException(
        '$platform receipt is missing fields: ${missingFields.join(', ')}');
  }
  final nonce = required('--nonce');
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce)) {
    throw ReceiptException('nonce must be 64 lowercase hexadecimal digits');
  }
  final cleanupStatus = required('--cleanup-status');
  final installStatus = required('--install-status');
  if (!const {'pass', 'fail'}.contains(cleanupStatus) ||
      !const {'pass', 'fail'}.contains(installStatus)) {
    throw ReceiptException('install and cleanup status must be pass or fail');
  }
  final installerKind = required('--installer-kind');
  final expectedKind = platform == 'android'
      ? 'apk-sha256'
      : platform == 'macos'
          ? 'app-tree-sha256'
          : 'ipa-sha256';
  if (installerKind != expectedKind) {
    throw ReceiptException('$platform requires installer kind $expectedKind');
  }
  final packageId = required('--package-id');
  if (packageId != 'dev.keybay.securityharness') {
    throw ReceiptException('unexpected qualification package identity');
  }
  if (required('--install-command') != 'flutter-test-controlled') {
    throw ReceiptException('unexpected install command identity');
  }
  return (
    output: required('--output'),
    platform: platform,
    selection: selection,
    executionClass: executionClass,
    nonce: nonce,
    subjectArchive: required('--subject-archive'),
    results: required('--results'),
    cleanupStatus: cleanupStatus,
    installerKind: installerKind,
    installerPath: required('--installer-path'),
    packageId: packageId,
    installCommand: 'flutter-test-controlled',
    installStatus: installStatus,
    fields: fields,
  );
}

Future<Map<String, Object?>> _buildReceipt(_Config config) async {
  final repo = File.fromUri(Platform.script).parent.parent.parent.absolute;
  final git = _firstExisting(['/usr/bin/git', '/bin/git']);
  final commit = await _run(
    git,
    ['-C', repo.path, 'rev-parse', 'HEAD'],
    cleanGitEnv: true,
  );
  final dirty = (await _run(
    git,
    ['-C', repo.path, 'status', '--porcelain', '--untracked-files=all'],
    cleanGitEnv: true,
  ))
      .isNotEmpty;
  if (dirty) {
    throw ReceiptException('release receipts require a clean suite checkout');
  }

  final output = File(config.output).absolute;
  await _requirePrivateParent(output);
  final subjectArchive = File(config.subjectArchive).absolute;
  _requireRegularFile(subjectArchive, 'subject archive');
  final python =
      _firstExisting(['/usr/bin/python3', '/opt/homebrew/bin/python3']);
  final subjectDigest = await _run(python, [
    '${repo.path}/tool/compare_pub_archives.py',
    '--digest',
    subjectArchive.path,
  ]);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(subjectDigest)) {
    throw ReceiptException('canonical subject digest was malformed');
  }
  final subjectIdentity = 'core-pub-content-sha256:$subjectDigest';

  final resultsFile = File(config.results).absolute;
  if (resultsFile.parent.path != output.parent.path) {
    throw ReceiptException('results must be retained beside the receipt');
  }
  _requireRegularFile(resultsFile, 'structured results');
  final resultBytes = await resultsFile.readAsBytes();
  if (resultBytes.length > 1024 * 1024) {
    throw ReceiptException('structured results exceed the 1 MiB cap');
  }
  final resultDigest = await _sha256(resultsFile);
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(resultBytes));
  } on FormatException {
    throw ReceiptException('structured results contain malformed JSON');
  }
  if (decoded is! Map<String, dynamic> ||
      decoded['schema'] != 'keybay.device-security-results' ||
      decoded['schema_version'] != 1 ||
      decoded['nonce'] != config.nonce ||
      decoded['subject'] != subjectIdentity ||
      decoded['selection'] != config.selection) {
    throw ReceiptException('structured results do not match this run/subject');
  }

  final selected = scenariosForSelection(config.selection);
  final expectedTestIds = selected
      .where((scenario) => !scenario.id.endsWith('-001'))
      .map((scenario) => scenario.id)
      .toSet();
  final resultStatuses = <String, String>{};
  final resultList = decoded['scenarios'];
  if (resultList is! List) {
    throw ReceiptException('structured results omitted scenarios');
  }
  for (final entry in resultList) {
    if (entry is! Map<String, dynamic> ||
        entry['id'] is! String ||
        entry['status'] is! String) {
      throw ReceiptException('structured scenario result was malformed');
    }
    final id = entry['id'] as String;
    final status = entry['status'] as String;
    if (!expectedTestIds.contains(id) ||
        !const {'pass', 'fail', 'blocked', 'skipped', 'inconclusive'}
            .contains(status) ||
        resultStatuses.containsKey(id)) {
      throw ReceiptException('unexpected or duplicate scenario result: $id');
    }
    resultStatuses[id] = status;
  }
  if (resultStatuses.keys.toSet().length != expectedTestIds.length ||
      !resultStatuses.keys.toSet().containsAll(expectedTestIds)) {
    throw ReceiptException('structured results omitted a required scenario');
  }

  final inventoryStatus = _inventoryStatus(config.platform, config.fields);
  final scenarios = <Map<String, String>>[];
  for (final scenario in selected) {
    scenarios.add({
      'id': scenario.id,
      'status': scenario.id.endsWith('-001')
          ? inventoryStatus
          : resultStatuses[scenario.id]!,
    });
  }
  final statuses = scenarios.map((scenario) => scenario['status']!).toList();
  final status = statuses.contains('fail')
      ? 'fail'
      : config.installStatus != 'pass' || config.cleanupStatus != 'pass'
          ? 'inconclusive'
          : statuses.every((value) => value == 'pass')
              ? 'pass'
              : statuses.contains('inconclusive')
                  ? 'inconclusive'
                  : 'blocked';

  final installer = FileSystemEntity.typeSync(
    File(config.installerPath).absolute.path,
    followLinks: false,
  );
  final installerPath = File(config.installerPath).absolute;
  final String installerDigest;
  if (config.installerKind == 'app-tree-sha256') {
    if (installer != FileSystemEntityType.directory) {
      throw ReceiptException('installer app must be a real directory');
    }
    installerDigest = await _treeDigest(Directory(installerPath.path), output);
  } else {
    if (installer != FileSystemEntityType.file) {
      throw ReceiptException('installer input must be a regular file');
    }
    installerDigest = await _sha256(installerPath);
  }

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

  return {
    'schema': 'keybay.device-security-receipt',
    'schema_version': 2,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'suite': {'commit': commit, 'clean': true},
    'subject': {
      'kind': 'core-pub-content-sha256',
      'name': 'keybay-core',
      'sha256': subjectDigest,
    },
    'run_nonce': config.nonce,
    'platform': config.platform,
    'selection': config.selection,
    'execution_class': config.executionClass,
    'status': status,
    'device': {
      'model': fields['model'],
      'build': fields['build_fingerprint'],
      'api_level': api,
      'security_patch': patch,
    },
    'installer': {
      'kind': config.installerKind,
      'sha256': installerDigest,
      'package_id': config.packageId,
      'command': config.installCommand,
      'status': config.installStatus,
    },
    'cleanup': {'status': config.cleanupStatus},
    'scenarios': scenarios,
    'evidence': [
      {
        'path': resultsFile.uri.pathSegments.last,
        'sha256': resultDigest,
        'bytes': resultBytes.length,
      }
    ],
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
            // 'unreported' is the adapter's sentinel for "sm get-fbe-mode
            // yielded nothing" — an unverified fact must not pass inventory.
            (fields['fbe'] ?? '') != '' &&
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
    throw ReceiptException('receipt parent must be a real directory');
  }
  final parentStat = await output.parent.stat();
  if ((parentStat.mode & 0x3f) != 0) {
    throw ReceiptException('receipt parent must not grant group/other access');
  }
}

void _requireRegularFile(File file, String label) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ReceiptException('$label must be a regular file');
  }
}

Future<String> _treeDigest(Directory root, File output) async {
  final records = <String>[];
  var totalBytes = 0;
  final entities = root.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  if (entities.length > 50000) {
    throw ReceiptException('installer tree contains too many entries');
  }
  for (final entity in entities) {
    final relative = entity.path.substring(root.path.length + 1);
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    final stat = entity.statSync();
    if (type == FileSystemEntityType.directory) {
      records.add(jsonEncode(['directory', relative, stat.mode & 0xfff]));
    } else if (type == FileSystemEntityType.link) {
      records.add(jsonEncode([
        'link',
        relative,
        stat.mode & 0xfff,
        Link(entity.path).targetSync(),
      ]));
    } else if (type == FileSystemEntityType.file) {
      totalBytes += stat.size;
      if (totalBytes > 1024 * 1024 * 1024) {
        throw ReceiptException('installer tree exceeds the 1 GiB cap');
      }
      records.add(jsonEncode([
        'file',
        relative,
        stat.mode & 0xfff,
        stat.size,
        await _sha256(File(entity.path)),
      ]));
    } else {
      throw ReceiptException('installer tree contains an unsupported entry');
    }
  }
  final identity = File('${output.path}.app-identity.tmp');
  try {
    await identity.create(exclusive: true);
    await identity.writeAsString('${records.join('\n')}\n', flush: true);
    return await _sha256(identity);
  } finally {
    if (identity.existsSync()) identity.deleteSync();
  }
}

Future<String> _sha256(File file) async {
  final before = file.statSync();
  for (final command in <(String, List<String>)>[
    ('/usr/bin/shasum', ['-a', '256', '--', file.path]),
    ('/usr/bin/sha256sum', ['--', file.path]),
    ('/bin/sha256sum', ['--', file.path]),
  ]) {
    if (!File(command.$1).existsSync()) continue;
    final output = await _run(command.$1, command.$2);
    final digest = output.split(RegExp(r'\s+')).first.toLowerCase();
    final after = file.statSync();
    if (before.size != after.size ||
        before.modified != after.modified ||
        before.changed != after.changed) {
      throw ReceiptException('artifact changed while hashing');
    }
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return digest;
  }
  throw ReceiptException('neither shasum nor sha256sum is available');
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
