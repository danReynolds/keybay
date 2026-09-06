/// Internal application-identity resolution for Keybay V2.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// How the current host application's identity was established.
enum ApplicationIdentitySource {
  operatingSystem,
  sourcePubspec,
  activatedPubspec,
  dartInstallPubspec,
  buildEmbedded,
  test,
}

/// The evidence-backed class of application identity for a host profile.
enum ApplicationIdentityAssurance {
  osEnforced(1),
  namespaceOnly(2);

  const ApplicationIdentityAssurance(this.wireCode);

  /// Frozen value used by identity-derived persistent addresses.
  final int wireCode;
}

/// One canonical application identity resolved before store metadata is read.
final class ApplicationIdentity {
  /// Creates an identity returned by a qualified platform resolver.
  ApplicationIdentity({
    required String stableValue,
    required this.source,
    required this.assurance,
  }) : stableValue = _validateApplicationId(stableValue);

  /// Canonical identity value bound into storage and cryptographic context.
  final String stableValue;

  /// Evidence source. This is diagnostic, not a storage selector.
  final ApplicationIdentitySource source;

  final ApplicationIdentityAssurance assurance;

  @override
  String toString() =>
      'ApplicationIdentity(source: ${source.name}, assurance: ${assurance.name})';
}

/// Stable internal identity-resolution failure classes.
enum ApplicationIdentityFailureCode {
  unavailable,
  invalidDeclaration,
  conflictingDeclarations,
  metadataTooLarge,
  metadataUnreadable,
}

/// A redacted internal application-identity failure.
final class ApplicationIdentityFailure implements Exception {
  const ApplicationIdentityFailure(this.code);

  final ApplicationIdentityFailureCode code;

  @override
  String toString() => 'ApplicationIdentityFailure(${code.name})';
}

/// Immutable process evidence used by the ordinary Dart identity resolver.
///
/// Production obtains this through [DartRuntimeIdentityInputs.currentProcess].
/// Explicit construction exists for deterministic boundary tests; it is not a
/// public Keybay SDK escape hatch or a runtime application selector.
final class DartRuntimeIdentityInputs {
  const DartRuntimeIdentityInputs({
    required this.script,
    required this.packageConfig,
    required this.resolvedExecutable,
    required this.embeddedApplicationId,
  });

  static Future<DartRuntimeIdentityInputs> currentProcess() async =>
      DartRuntimeIdentityInputs(
        script: Platform.script,
        packageConfig: await Isolate.packageConfig,
        resolvedExecutable: Uri.file(Platform.resolvedExecutable),
        embeddedApplicationId: _embeddedApplicationId,
      );

  final Uri script;
  final Uri? packageConfig;
  final Uri resolvedExecutable;
  final String embeddedApplicationId;
}

/// Resolves namespace-only identities for ordinary Dart host applications.
///
/// Source, activated, and Dart-installed execution read only metadata rooted in
/// the executable's owning package or recognized application bundle. Other AOT
/// execution requires a declaration embedded by the Keybay build integration.
/// The current working directory, executable name, and process environment are
/// never consulted.
final class DartApplicationIdentityResolver {
  DartApplicationIdentityResolver(this._inputs);

  static Future<ApplicationIdentity> resolveCurrentProcess() async =>
      DartApplicationIdentityResolver(
        await DartRuntimeIdentityInputs.currentProcess(),
      ).resolve();

  static const int maximumPubspecBytes = 64 * 1024;

  final DartRuntimeIdentityInputs _inputs;

  ApplicationIdentity resolve() {
    final embedded = _inputs.embeddedApplicationId.isEmpty
        ? null
        : _validateApplicationId(_inputs.embeddedApplicationId);
    final aotExecutable = _canonicalAotImage();
    if (aotExecutable != null) {
      final installed = _resolveDartInstallDeclaration(aotExecutable);
      if (embedded != null &&
          installed != null &&
          embedded != installed.value) {
        throw const ApplicationIdentityFailure(
          ApplicationIdentityFailureCode.conflictingDeclarations,
        );
      }
      if (installed != null) {
        return ApplicationIdentity(
          stableValue: installed.value,
          source: installed.source,
          assurance: ApplicationIdentityAssurance.namespaceOnly,
        );
      }
      if (embedded != null) {
        return ApplicationIdentity(
          stableValue: embedded,
          source: ApplicationIdentitySource.buildEmbedded,
          assurance: ApplicationIdentityAssurance.namespaceOnly,
        );
      }
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.unavailable,
      );
    }

    final local = _resolveLocalDeclaration();

    if (embedded != null && local != null && embedded != local.value) {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.conflictingDeclarations,
      );
    }
    if (local != null) {
      return ApplicationIdentity(
        stableValue: local.value,
        source: local.source,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      );
    }
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }

  File? _canonicalAotImage() {
    if (_inputs.script.scheme != 'file' ||
        _inputs.resolvedExecutable.scheme != 'file') {
      return null;
    }
    try {
      final script = File.fromUri(_inputs.script).resolveSymbolicLinksSync();
      final executable = File.fromUri(
        _inputs.resolvedExecutable,
      ).resolveSymbolicLinksSync();
      if (script == executable) return File(executable);
      // A separate AOT module is the executing image, while resolvedExecutable
      // names dartaotruntime. Recognize its native image header, not a suffix or
      // launch argument. Source and activated launches still use owning metadata.
      final image = File(script);
      final handle = image.openSync();
      try {
        final bytes = handle.readSync(4);
        if (bytes.length != 4) return null;
        final magic =
            bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24;
        return switch (magic) {
          0x464c457f || 0xfeedfacf || 0xfeedface => image, // ELF or Mach-O.
          _ => null,
        };
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return null;
    }
  }

  _LocalDeclaration? _resolveDartInstallDeclaration(File executable) {
    try {
      final binDirectory = executable.parent;
      if (_basename(binDirectory) != 'bin') return null;
      final bundleDirectory = binDirectory.parent;
      if (_basename(bundleDirectory) != 'bundle') return null;
      final appBundleDirectory = bundleDirectory.parent;
      if (!_hasDartInstallBundleShape(appBundleDirectory)) return null;

      final lock = File(_join(appBundleDirectory.path, ['pubspec.lock']));
      if (lock.statSync().type != FileSystemEntityType.file) {
        throw const ApplicationIdentityFailure(
          ApplicationIdentityFailureCode.metadataUnreadable,
        );
      }
      return _LocalDeclaration(
        value: _readApplicationId(
          File(_join(appBundleDirectory.path, ['pubspec.yaml'])),
        ),
        source: ApplicationIdentitySource.dartInstallPubspec,
      );
    } on ApplicationIdentityFailure {
      rethrow;
    } on FileSystemException {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.metadataUnreadable,
      );
    }
  }

  _LocalDeclaration? _resolveLocalDeclaration() {
    final script = _inputs.script;
    if (script.scheme != 'file') return null;

    try {
      final scriptFile = File.fromUri(script);
      if (scriptFile.path.endsWith('.dart')) {
        final pubspec = _findOwningPubspec(scriptFile);
        return _LocalDeclaration(
          value: _readApplicationId(pubspec),
          source: ApplicationIdentitySource.sourcePubspec,
        );
      }

      final packageConfig = _inputs.packageConfig;
      if (packageConfig == null || packageConfig.scheme != 'file') return null;
      final packageConfigFile = File.fromUri(packageConfig);
      if (packageConfigFile.uri.pathSegments.lastOrNull !=
          'package_config.json') {
        return null;
      }
      final dartTool = packageConfigFile.parent;
      if (dartTool.uri.pathSegments.lastNonEmptyOrNull != '.dart_tool') {
        return null;
      }
      final packageRoot = dartTool.parent;
      final canonicalRoot = packageRoot.resolveSymbolicLinksSync();
      final canonicalScript = scriptFile.resolveSymbolicLinksSync();
      final activationRoot = _join(canonicalRoot, <String>[
        '.dart_tool',
        'pub',
        'bin',
      ]);
      if (!_isWithin(canonicalScript, activationRoot)) return null;

      return _LocalDeclaration(
        value: _readApplicationId(File(_join(canonicalRoot, ['pubspec.yaml']))),
        source: ApplicationIdentitySource.activatedPubspec,
      );
    } on ApplicationIdentityFailure {
      rethrow;
    } on FileSystemException {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.metadataUnreadable,
      );
    }
  }

  File _findOwningPubspec(File script) {
    var directory = Directory(script.resolveSymbolicLinksSync()).parent;
    for (var depth = 0; depth < 64; depth++) {
      final candidate = File(_join(directory.path, ['pubspec.yaml']));
      if (candidate.existsSync()) return candidate;
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }

  String _readApplicationId(File pubspec) {
    try {
      final stat = pubspec.statSync();
      if (stat.type != FileSystemEntityType.file) {
        throw const ApplicationIdentityFailure(
          ApplicationIdentityFailureCode.metadataUnreadable,
        );
      }
      if (stat.size > maximumPubspecBytes) {
        throw const ApplicationIdentityFailure(
          ApplicationIdentityFailureCode.metadataTooLarge,
        );
      }
      final handle = pubspec.openSync();
      final List<int> bytes;
      try {
        if (handle.lengthSync() > maximumPubspecBytes) {
          throw const ApplicationIdentityFailure(
            ApplicationIdentityFailureCode.metadataTooLarge,
          );
        }
        bytes = handle.readSync(maximumPubspecBytes + 1);
        if (bytes.length > maximumPubspecBytes) {
          throw const ApplicationIdentityFailure(
            ApplicationIdentityFailureCode.metadataTooLarge,
          );
        }
      } finally {
        handle.closeSync();
      }
      final text = utf8.decode(bytes, allowMalformed: false);
      return _parsePubspecDeclaration(text);
    } on ApplicationIdentityFailure {
      rethrow;
    } on FormatException {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.invalidDeclaration,
      );
    } on FileSystemException {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.metadataUnreadable,
      );
    }
  }
}

bool _hasDartInstallBundleShape(Directory appBundle) {
  final leaf = _basename(appBundle);
  if (leaf == 'local') {
    return _isDartInstallPackageDirectory(appBundle.parent);
  }

  final sourceDirectory = appBundle.parent;
  final source = _basename(sourceDirectory);
  if (leaf.isEmpty || (source != 'hosted' && source != 'git')) return false;
  return _isDartInstallPackageDirectory(sourceDirectory.parent);
}

bool _isDartInstallPackageDirectory(Directory packageDirectory) =>
    _basename(packageDirectory).isNotEmpty &&
    _basename(packageDirectory.parent) == 'app-bundles' &&
    _basename(packageDirectory.parent.parent) == 'install';

String _basename(Directory directory) =>
    directory.uri.pathSegments.lastNonEmptyOrNull ?? '';

const String _embeddedApplicationId = String.fromEnvironment(
  'keybay.application_id',
);

final RegExp _applicationIdGrammar = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$',
);

String _validateApplicationId(String value) {
  if (!_applicationIdGrammar.hasMatch(value)) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.invalidDeclaration,
    );
  }
  return value;
}

String _parsePubspecDeclaration(String text) {
  final lines = const LineSplitter().convert(text);
  final keybayHeaders = <int>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (RegExp(r'^keybay:[ ]*(?:#.*)?$').hasMatch(line)) {
      keybayHeaders.add(index);
    } else if (RegExp(
      r'''^(?:keybay|["']keybay["'])[ \t]*:''',
    ).hasMatch(line)) {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.invalidDeclaration,
      );
    }
  }
  if (keybayHeaders.isEmpty) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }
  if (keybayHeaders.length != 1) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.invalidDeclaration,
    );
  }

  String? applicationId;
  for (var index = keybayHeaders.single + 1; index < lines.length; index++) {
    final line = lines[index];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ') && !line.startsWith('\t')) break;
    if (line.contains('\t')) {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.invalidDeclaration,
      );
    }
    final match = RegExp(
      r'^  application_id: ([A-Za-z0-9][A-Za-z0-9._-]{0,119}) *$',
    ).firstMatch(line);
    if (match != null) {
      if (applicationId != null) {
        throw const ApplicationIdentityFailure(
          ApplicationIdentityFailureCode.invalidDeclaration,
        );
      }
      applicationId = match.group(1)!;
    } else if (RegExp(
      r'''^(?:application_id|["']application_id["'])[ \t]*:''',
    ).hasMatch(line.trimLeft())) {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.invalidDeclaration,
      );
    }
  }
  if (applicationId == null) {
    throw const ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.unavailable,
    );
  }
  return _validateApplicationId(applicationId);
}

String _join(String root, List<String> components) {
  var result = root;
  for (final component in components) {
    if (!result.endsWith(Platform.pathSeparator)) {
      result += Platform.pathSeparator;
    }
    result += component;
  }
  return result;
}

bool _isWithin(String path, String directory) {
  final prefix = directory.endsWith(Platform.pathSeparator)
      ? directory
      : '$directory${Platform.pathSeparator}';
  return path.startsWith(prefix);
}

final class _LocalDeclaration {
  const _LocalDeclaration({required this.value, required this.source});

  final String value;
  final ApplicationIdentitySource source;
}

extension on List<String> {
  String? get lastOrNull => isEmpty ? null : last;

  String? get lastNonEmptyOrNull {
    for (var index = length - 1; index >= 0; index--) {
      if (this[index].isNotEmpty) return this[index];
    }
    return null;
  }
}
