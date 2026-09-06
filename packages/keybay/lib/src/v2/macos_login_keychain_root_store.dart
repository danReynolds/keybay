/// Narrow V2 custody seam for the macOS login-Keychain platform root.
library;

import 'dart:typed_data';

import '../ffi/keychain.dart';

/// Frozen login-Keychain service for V2 application roots.
const String v2MacOSLoginKeychainService = 'dev.keybay.v2.platform-root';

/// Non-secret label shown by Keychain tools.
const String v2MacOSLoginKeychainLabel = 'Keybay application store root';

/// Exact V2 login-Keychain root record size (magic + domain + root).
const int v2MacOSLoginKeychainRootRecordBytes = 72;

/// Maximum provider value copied into Dart for V2 root processing.
///
/// The valid shape remains exactly [v2MacOSLoginKeychainRootRecordBytes]. The
/// wider fixed ceiling lets reset remove modest malformed state while bounding
/// a hostile Keychain value before Dart allocation.
const int v2MacOSLoginKeychainMaxRootRecordBytes = 4096;

/// Exact operations the macOS V2 protector needs from its fixed file Keychain.
///
/// The service is not a caller input. Implementations address one item only by
/// the already-derived provider address and never enumerate or clear a service.
abstract interface class MacOSLoginKeychainRootStore {
  Future<Uint8List?> read(String providerAddress);

  Future<bool> createIfAbsent(String providerAddress, Uint8List value);

  Future<bool> exists(String providerAddress);

  Future<void> delete(String providerAddress);
}

/// The real root store pinned to the effective account's explicit login file.
final class AppleMacOSLoginKeychainRootStore
    implements MacOSLoginKeychainRootStore {
  AppleMacOSLoginKeychainRootStore({required String accountHome})
    : _keychain = AppleKeychainApi.fileKeychainAt(
        '$accountHome/Library/Keychains/login.keychain-db',
      );

  final AppleKeychainApi _keychain;

  @override
  Future<Uint8List?> read(String providerAddress) => _keychain.getBounded(
    v2MacOSLoginKeychainService,
    providerAddress,
    maxValueBytes: v2MacOSLoginKeychainMaxRootRecordBytes,
  );

  @override
  Future<bool> createIfAbsent(String providerAddress, Uint8List value) =>
      _keychain.addIfAbsent(
        v2MacOSLoginKeychainService,
        providerAddress,
        value,
        label: v2MacOSLoginKeychainLabel,
      );

  @override
  Future<bool> exists(String providerAddress) =>
      _keychain.exists(v2MacOSLoginKeychainService, providerAddress);

  @override
  Future<void> delete(String providerAddress) =>
      _keychain.delete(v2MacOSLoginKeychainService, providerAddress);
}
