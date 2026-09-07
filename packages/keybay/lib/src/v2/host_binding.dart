/// Internal immutable host binding for Keybay V2.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'application_identity.dart';

/// A fixed qualified host profile, not a bag of optional capabilities.
final class HostProfile {
  HostProfile(String code) : code = _validateProfileCode(code);

  /// Stable non-secret qualification label.
  final String code;

  @override
  bool operator ==(Object other) => other is HostProfile && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'HostProfile($code)';
}

/// A non-secret SHA-256 commitment to one canonical storage domain.
final class StorageDomain {
  StorageDomain._(Uint8List commitment) : _commitment = commitment;

  final Uint8List _commitment;

  /// Stable text form suitable for an internal provider record.
  String get commitment => base64Url.encode(_commitment).replaceAll('=', '');

  /// Returns the canonical raw commitment for authenticated format context.
  Uint8List copyBytes() => Uint8List.fromList(_commitment);

  @override
  bool operator ==(Object other) {
    if (other is! StorageDomain ||
        other._commitment.length != _commitment.length) {
      return false;
    }
    var difference = 0;
    for (var index = 0; index < _commitment.length; index++) {
      difference |= _commitment[index] ^ other._commitment[index];
    }
    return difference == 0;
  }

  @override
  int get hashCode => Object.hashAll(_commitment);

  @override
  String toString() => 'StorageDomain(<redacted>)';
}

/// The identity, profile, physical file root, and storage-domain commitment
/// selected before any store bytes or provider state are read.
final class ResolvedApplicationBinding {
  factory ResolvedApplicationBinding.derive({
    required ApplicationIdentity identity,
    required HostProfile profile,
    required Uri canonicalFileRoot,
  }) {
    _validateCanonicalFileRoot(canonicalFileRoot);
    return ResolvedApplicationBinding._(
      identity: identity,
      profile: profile,
      canonicalFileRoot: canonicalFileRoot,
      domain: _deriveStorageDomain(
        label: 'keybay:v2:storage-domain',
        identity: identity,
        profile: profile,
        location: canonicalFileRoot.toString(),
      ),
    );
  }

  /// Binds one fixed location inside an OS-owned application container.
  ///
  /// The qualified host chooses [containerRelativeRoot]; application input and
  /// stored metadata never select it. The current physical root remains part
  /// of this resolved binding, but OS relocation does not change the domain.
  factory ResolvedApplicationBinding.forApplicationContainer({
    required ApplicationIdentity identity,
    required HostProfile profile,
    required Uri canonicalFileRoot,
    required Uri containerRelativeRoot,
  }) {
    _validateCanonicalFileRoot(canonicalFileRoot);
    _validateContainerRelativeRoot(containerRelativeRoot);
    return ResolvedApplicationBinding._(
      identity: identity,
      profile: profile,
      canonicalFileRoot: canonicalFileRoot,
      domain: _deriveStorageDomain(
        label: 'keybay:v2:container-storage-domain',
        identity: identity,
        profile: profile,
        location: containerRelativeRoot.toString(),
      ),
    );
  }

  const ResolvedApplicationBinding._({
    required this.identity,
    required this.profile,
    required this.canonicalFileRoot,
    required this.domain,
  });

  final ApplicationIdentity identity;
  final HostProfile profile;
  final Uri canonicalFileRoot;
  final StorageDomain domain;

  /// Provider address material deliberately excludes the file-root commitment.
  ///
  /// Two launches with the same identity/profile contend for one provider
  /// record. Path-bound profiles detect a changed root through its domain;
  /// container-bound profiles retain the domain across OS container relocation.
  String get providerAddress => base64Url
      .encode(
        const DartSha256().hashSync(<int>[
          ...utf8.encode('keybay:v2:provider-address'),
          0,
          ..._lengthPrefixed(utf8.encode(identity.stableValue)),
          ..._lengthPrefixed(<int>[identity.assurance.wireCode]),
          ..._lengthPrefixed(utf8.encode(profile.code)),
        ]).bytes,
      )
      .replaceAll('=', '');

  @override
  String toString() =>
      'ResolvedApplicationBinding(${identity.source.name}, ${profile.code}, <redacted>)';
}

final RegExp _profileCodeGrammar = RegExp(r'^[a-z0-9][a-z0-9._-]{0,119}$');

String _validateProfileCode(String code) {
  if (!_profileCodeGrammar.hasMatch(code)) {
    throw ArgumentError.value(code, 'code', 'invalid host profile code');
  }
  return code;
}

void _validateCanonicalFileRoot(Uri root) {
  if (root.scheme != 'file' ||
      !root.isAbsolute ||
      root.hasQuery ||
      root.hasFragment ||
      !root.path.endsWith('/') ||
      root.normalizePath() != root ||
      root.toString().length > 4096) {
    throw ArgumentError.value(
      '<redacted>',
      'canonicalFileRoot',
      'must be a normalized absolute file directory URI',
    );
  }
}

void _validateContainerRelativeRoot(Uri root) {
  final components = root.pathSegments;
  if (root.isAbsolute ||
      root.hasAuthority ||
      root.hasAbsolutePath ||
      root.hasQuery ||
      root.hasFragment ||
      !root.path.endsWith('/') ||
      root.normalizePath() != root ||
      root.toString().length > 4096 ||
      components.length < 2 ||
      components
          .take(components.length - 1)
          .any(
            (component) =>
                component.isEmpty ||
                component == '.' ||
                component == '..' ||
                component.contains(RegExp(r'[/\\\x00-\x1f\x7f]')),
          )) {
    throw ArgumentError.value(
      '<redacted>',
      'containerRelativeRoot',
      'must be a normalized relative directory URI within the application container',
    );
  }
}

StorageDomain _deriveStorageDomain({
  required String label,
  required ApplicationIdentity identity,
  required HostProfile profile,
  required String location,
}) {
  final encoding = BytesBuilder(copy: false)
    ..add(utf8.encode(label))
    ..addByte(0)
    ..add(_lengthPrefixed(utf8.encode(identity.stableValue)))
    ..add(_lengthPrefixed(<int>[identity.assurance.wireCode]))
    ..add(_lengthPrefixed(utf8.encode(profile.code)))
    ..add(_lengthPrefixed(utf8.encode(location)));
  final digest = const DartSha256().hashSync(encoding.takeBytes()).bytes;
  return StorageDomain._(Uint8List.fromList(digest));
}

Uint8List _lengthPrefixed(List<int> bytes) {
  final length = ByteData(4)..setUint32(0, bytes.length);
  return Uint8List.fromList(<int>[...length.buffer.asUint8List(), ...bytes]);
}
