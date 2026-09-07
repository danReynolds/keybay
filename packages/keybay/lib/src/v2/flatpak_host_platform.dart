/// Fixed Flatpak application identity, private files, and Secret Portal binding.
library;

import 'dart:convert';
import 'dart:io';

import 'application_identity.dart';
import 'flatpak_secret_portal_protector.dart';
import 'host_platform.dart';
import 'linux_secret_portal.dart';
import 'platform_protector.dart';
import 'posix_store_files.dart';

const String flatpakProfileCode = 'linux.flatpak.secret-portal-file.v1';
const int _maximumInfoBytes = 64 * 1024;
const String _storeDirectory = 'keybay-v2';
final RegExp _flatpakId = RegExp(
  r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+\.[A-Za-z_-][A-Za-z0-9_-]*$',
);

/// Any marker, including malformed or unsupported metadata, selects Flatpak.
/// It must never cause a retry through the ordinary Linux profile.
bool currentProcessHasFlatpakMarker() =>
    FileSystemEntity.typeSync('/.flatpak-info', followLinks: false) !=
    FileSystemEntityType.notFound;

final class FlatpakHostPlatform implements HostPlatform {
  FlatpakHostPlatform()
    : _isLinux = Platform.isLinux,
      _readInfo = _readCurrentInfo,
      _portal = DbusLinuxSecretPortal();

  /// Internal assembly seam; production always reads the fixed OS marker.
  FlatpakHostPlatform.test({
    required List<int> Function() readInfo,
    required LinuxSecretPortal portal,
    bool isLinux = true,
  }) : _isLinux = isLinux,
       _readInfo = readInfo,
       _portal = portal;

  final bool _isLinux;
  final List<int> Function() _readInfo;
  final LinuxSecretPortal _portal;

  @override
  Future<ResolvedHost> resolve() async {
    if (!_isLinux) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }
    final FlatpakApplicationInfo info;
    try {
      info = FlatpakApplicationInfo.parse(_readInfo());
    } on ApplicationIdentityFailure {
      rethrow;
    } on Object {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.metadataUnreadable,
      );
    }

    // Flatpak creates instance-path/data itself. Do not resolve symlinks or
    // synthesize missing ancestors; the POSIX adapter pins each component and
    // creates only our private final leaf when initialization needs it.
    final binding = ResolvedApplicationBinding.derive(
      identity: info.identity,
      profile: HostProfile(flatpakProfileCode),
      canonicalFileRoot: info.fileRoot,
    );
    return ResolvedHost(
      binding: binding,
      files: PosixStoreFiles(
        binding: binding,
        canonicalFileRoot: info.fileRoot,
      ),
      protector: FlatpakSecretPortalProtector(
        binding: binding,
        portal: _portal,
      ),
    );
  }
}

/// The two facts supplied by Flatpak, never by environment or store bytes.
final class FlatpakApplicationInfo {
  const FlatpakApplicationInfo._(this.identity, this.fileRoot);

  factory FlatpakApplicationInfo.parse(List<int> bytes) {
    if (bytes.length > _maximumInfoBytes) {
      throw const ApplicationIdentityFailure(
        ApplicationIdentityFailureCode.metadataTooLarge,
      );
    }
    try {
      final text = utf8.decode(bytes);
      if (text.contains('\u0000')) _invalidInfo();
      final groups = <String, Map<String, String>>{};
      Map<String, String>? group;
      for (final raw in const LineSplitter().convert(text)) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line.startsWith('[') && line.endsWith(']')) {
          final name = line.substring(1, line.length - 1);
          if (name.isEmpty || groups.containsKey(name)) _invalidInfo();
          group = <String, String>{};
          groups[name] = group;
          continue;
        }
        final separator = line.indexOf('=');
        if (group == null || separator < 1) _invalidInfo();
        final key = line.substring(0, separator).trim();
        if (group.containsKey(key)) _invalidInfo();
        group[key] = line.substring(separator + 1).trim();
      }
      final name = groups['Application']?['name'];
      final encodedPath = groups['Instance']?['instance-path'];
      if (name == null || encodedPath == null || !_flatpakId.hasMatch(name)) {
        _invalidInfo();
      }
      final identity = ApplicationIdentity(
        stableValue: name,
        source: ApplicationIdentitySource.operatingSystem,
        assurance: ApplicationIdentityAssurance.osEnforced,
      );
      final path = _unescape(encodedPath);
      if (!path.startsWith('/') ||
          path.length > 3800 ||
          path.codeUnits.any((unit) => unit < 32 || unit == 127) ||
          path
              .substring(1)
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..')) {
        _invalidInfo();
      }
      // Flatpak can bind a host xdg-data subdirectory over this exact private
      // target. Refuse that narrow override instead of managing a shared root.
      final grants = groups['Context']?['filesystems'];
      if (grants != null) {
        for (final entry in grants.split(';')) {
          final target = entry.replaceFirst(RegExp(r':(ro|rw|create)$'), '');
          if (target == 'xdg-data/$_storeDirectory' ||
              target.startsWith('xdg-data/$_storeDirectory/')) {
            _invalidInfo();
          }
        }
      }
      return FlatpakApplicationInfo._(
        identity,
        Uri.directory('$path/data/$_storeDirectory'),
      );
    } on ApplicationIdentityFailure {
      rethrow;
    } on Object {
      _invalidInfo();
    }
  }

  final ApplicationIdentity identity;
  final Uri fileRoot;
}

List<int> _readCurrentInfo() {
  if (FileSystemEntity.typeSync('/.flatpak-info', followLinks: false) !=
      FileSystemEntityType.file) {
    _invalidInfo();
  }
  final file = File('/.flatpak-info').openSync();
  try {
    return file.readSync(_maximumInfoBytes + 1);
  } finally {
    file.closeSync();
  }
}

String _unescape(String value) {
  final result = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    var character = value[index];
    if (character == '\\') {
      if (++index == value.length) _invalidInfo();
      character = switch (value[index]) {
        's' => ' ',
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '\\' => '\\',
        _ => _invalidInfo(),
      };
    }
    result.write(character);
  }
  return result.toString();
}

Never _invalidInfo() => throw const ApplicationIdentityFailure(
  ApplicationIdentityFailureCode.unavailable,
);
