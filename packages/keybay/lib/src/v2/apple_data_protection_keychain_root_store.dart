/// Narrow V2 custody seam for an Apple Data Protection Keychain root.
library;

import 'dart:typed_data';

import '../ffi/keychain.dart';

/// Frozen service for V2 roots in an exact signed application-identifier group.
const String v2AppleDataProtectionRootService =
    'dev.keybay.v2.data-protection-root';

/// Non-secret label shown by Keychain tools.
const String v2AppleDataProtectionRootLabel = 'Keybay application store root';

/// Exact root record size: magic + storage-domain commitment + root.
const int v2AppleDataProtectionRootRecordBytes = 72;

/// Bounded read ceiling for malformed state at the exact V2 address.
const int v2AppleDataProtectionMaxRootRecordBytes = 4096;

/// The four operations required for one fixed V2 root item.
///
/// The service and signed access group belong to the implementation. The
/// protector supplies only its already-derived provider address and never
/// enumerates or clears the service.
abstract interface class DataProtectionKeychainRootStore {
  Future<Uint8List?> read(String providerAddress);

  Future<bool> createIfAbsent(String providerAddress, Uint8List value);

  Future<bool> exists(String providerAddress);

  Future<void> delete(String providerAddress);
}

/// The real root store fixed to one signed application-identifier group.
final class AppleDataProtectionKeychainRootStore
    implements DataProtectionKeychainRootStore {
  AppleDataProtectionKeychainRootStore({
    required String exactApplicationIdentifierAccessGroup,
  }) : _keychain = AppleKeychainApi.v2DataProtection(
         exactApplicationIdentifierAccessGroup:
             exactApplicationIdentifierAccessGroup,
       );

  final AppleKeychainApi _keychain;

  @override
  Future<Uint8List?> read(String providerAddress) => _keychain.getBounded(
    v2AppleDataProtectionRootService,
    providerAddress,
    maxValueBytes: v2AppleDataProtectionMaxRootRecordBytes,
  );

  @override
  Future<bool> createIfAbsent(String providerAddress, Uint8List value) =>
      _keychain.addIfAbsent(
        v2AppleDataProtectionRootService,
        providerAddress,
        value,
        label: v2AppleDataProtectionRootLabel,
      );

  @override
  Future<bool> exists(String providerAddress) =>
      _keychain.exists(v2AppleDataProtectionRootService, providerAddress);

  @override
  Future<void> delete(String providerAddress) =>
      _keychain.delete(v2AppleDataProtectionRootService, providerAddress);
}
