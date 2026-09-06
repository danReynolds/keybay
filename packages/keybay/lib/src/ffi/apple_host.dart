/// Narrow public Apple host APIs used by the V2 signed-application profiles.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Public, signed bundle and filesystem facts shared by iOS and macOS.
///
/// The iOS factory deliberately does not bind or call `SecTask`. Its exact
/// application-identifier is read from a build-expanded Info.plist value,
/// which is part of the signed application bundle. The Data Protection
/// Keychain remains the authority that enforces access to that exact group.
final class AppleHostApi {
  AppleHostApi.ios() : this._(bindMacOSEntitlements: false);

  AppleHostApi.macOS() : this._(bindMacOSEntitlements: true);

  AppleHostApi._({required bool bindMacOSEntitlements})
    : _bindMacOSEntitlements = bindMacOSEntitlements,
      _coreFoundation = Platform.isIOS
          ? DynamicLibrary.process()
          : DynamicLibrary.open(
              '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
            ),
      _foundation = Platform.isIOS
          ? DynamicLibrary.process()
          : DynamicLibrary.open(
              '/System/Library/Frameworks/Foundation.framework/Foundation',
            ),
      _security = bindMacOSEntitlements
          ? DynamicLibrary.open(
              '/System/Library/Frameworks/Security.framework/Security',
            )
          : null {
    _bind();
  }

  final bool _bindMacOSEntitlements;
  final DynamicLibrary _coreFoundation;
  final DynamicLibrary _foundation;
  final DynamicLibrary? _security;

  late final Pointer<Void> Function() _cfBundleGetMainBundle;
  late final Pointer<Void> Function(Pointer<Void>) _cfBundleGetIdentifier;
  late final Pointer<Void> Function(Pointer<Void>) _cfBundleGetInfoDictionary;
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
  _cfDictionaryGetValue;
  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    int,
  )
  _cfStringCreateWithBytes;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, int)
  _cfStringGetCString;
  late final int Function(Pointer<Void>) _cfGetTypeId;
  late final int Function() _cfStringGetTypeId;
  late final int Function() _cfBooleanGetTypeId;
  late final int Function(Pointer<Void>) _cfBooleanGetValue;
  late final void Function(Pointer<Void>) _cfRelease;
  late final int Function(Pointer<Void>) _cfArrayGetCount;
  late final Pointer<Void> Function(Pointer<Void>, int) _cfArrayGetValueAtIndex;
  late final Pointer<Void> Function(int, int, int) _searchPaths;
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int)
  _cfUrlCreateFromFileSystemRepresentation;
  late final int Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Void>>,
  )
  _cfUrlSetResourceProperty;
  late final int Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Void>>,
  )
  _cfUrlCopyResourceProperty;
  late final void Function(Pointer<Void>, Pointer<Void>)
  _cfUrlClearResourcePropertyCache;
  late final Pointer<Void> _backupExclusionKey;
  late final Pointer<Void> _cfBooleanTrue;

  Pointer<Void> Function(Pointer<Void>)? _secTaskCreateFromSelf;
  Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>)?
  _secTaskCopyValueForEntitlement;

  void _bind() {
    _cfBundleGetMainBundle = _coreFoundation
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'CFBundleGetMainBundle',
        );
    _cfBundleGetIdentifier = _coreFoundation
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('CFBundleGetIdentifier');
    _cfBundleGetInfoDictionary = _coreFoundation
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
        >('CFBundleGetInfoDictionary');
    _cfDictionaryGetValue = _coreFoundation
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
        >('CFDictionaryGetValue');
    _cfStringCreateWithBytes = _coreFoundation
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Uint8>,
            IntPtr,
            Uint32,
            Uint8,
          ),
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int, int)
        >('CFStringCreateWithBytes');
    _cfStringGetCString = _coreFoundation
        .lookupFunction<
          Uint8 Function(Pointer<Void>, Pointer<Uint8>, IntPtr, Uint32),
          int Function(Pointer<Void>, Pointer<Uint8>, int, int)
        >('CFStringGetCString');
    _cfGetTypeId = _coreFoundation
        .lookupFunction<
          UintPtr Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFGetTypeID');
    _cfStringGetTypeId = _coreFoundation
        .lookupFunction<UintPtr Function(), int Function()>(
          'CFStringGetTypeID',
        );
    _cfBooleanGetTypeId = _coreFoundation
        .lookupFunction<UintPtr Function(), int Function()>(
          'CFBooleanGetTypeID',
        );
    _cfBooleanGetValue = _coreFoundation
        .lookupFunction<
          Uint8 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFBooleanGetValue');
    _cfRelease = _coreFoundation
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CFRelease');
    _cfArrayGetCount = _coreFoundation
        .lookupFunction<
          IntPtr Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFArrayGetCount');
    _cfArrayGetValueAtIndex = _coreFoundation
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, IntPtr),
          Pointer<Void> Function(Pointer<Void>, int)
        >('CFArrayGetValueAtIndex');
    _searchPaths = _foundation
        .lookupFunction<
          Pointer<Void> Function(UintPtr, UintPtr, Uint8),
          Pointer<Void> Function(int, int, int)
        >('NSSearchPathForDirectoriesInDomains');
    _cfUrlCreateFromFileSystemRepresentation = _coreFoundation
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, IntPtr, Uint8),
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int, int)
        >('CFURLCreateFromFileSystemRepresentation');
    _cfUrlSetResourceProperty = _coreFoundation
        .lookupFunction<
          Uint8 Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
          )
        >('CFURLSetResourcePropertyForKey');
    _cfUrlCopyResourceProperty = _coreFoundation
        .lookupFunction<
          Uint8 Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Void>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
          )
        >('CFURLCopyResourcePropertyForKey');
    _cfUrlClearResourcePropertyCache = _coreFoundation
        .lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
        >('CFURLClearResourcePropertyCacheForKey');
    _backupExclusionKey = _cfConstant(
      _coreFoundation,
      'kCFURLIsExcludedFromBackupKey',
    );
    _cfBooleanTrue = _cfConstant(_coreFoundation, 'kCFBooleanTrue');

    if (_bindMacOSEntitlements) {
      final security = _security!;
      _secTaskCreateFromSelf = security
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>)
          >('SecTaskCreateFromSelf');
      _secTaskCopyValueForEntitlement = security
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Void>>,
            )
          >('SecTaskCopyValueForEntitlement');
    }
  }

  /// The signed bundle's public `CFBundleIdentifier`.
  String bundleIdentifier() {
    final bundle = _cfBundleGetMainBundle();
    if (bundle == nullptr) throw const AppleHostApiFailure();
    final value = _cfBundleGetIdentifier(bundle);
    return _requiredString(value);
  }

  /// Reads one nonlocalized public signed Info.plist string.
  ///
  /// This deliberately reads the raw processed dictionary. The convenience
  /// `CFBundleGetValueForInfoDictionaryKey` API may substitute a value from
  /// `InfoPlist.strings`, which would make storage identity locale-dependent.
  String infoString(String key) {
    final bundle = _cfBundleGetMainBundle();
    if (bundle == nullptr) throw const AppleHostApiFailure();
    final dictionary = _cfBundleGetInfoDictionary(bundle);
    if (dictionary == nullptr) throw const AppleHostApiFailure();
    final keyRef = _createString(key);
    try {
      return _requiredString(_cfDictionaryGetValue(dictionary, keyRef));
    } finally {
      _cfRelease(keyRef);
    }
  }

  /// Returns the public Foundation user Application Support directory.
  String applicationSupportDirectory() {
    const applicationSupportDirectory = 14;
    const userDomainMask = 1;
    final paths = _searchPaths(applicationSupportDirectory, userDomainMask, 1);
    if (paths == nullptr || _cfArrayGetCount(paths) != 1) {
      throw const AppleHostApiFailure();
    }
    return _requiredString(_cfArrayGetValueAtIndex(paths, 0));
  }

  /// The exact signed application-identifier entitlement for macOS.
  ///
  /// This never derives identity from `keychain-access-groups`, so a shared or
  /// reordered group cannot become the private Keybay root namespace.
  String macOSSignedApplicationIdentifier() {
    return macOSSignedApplicationIdentifierOrNull() ??
        (throw const AppleHostApiFailure());
  }

  /// Probes the exact signed application identifier for profile dispatch.
  ///
  /// Null means both supported application-identifier spellings and the
  /// keychain-access-groups entitlement are absent. A group-only configuration
  /// cannot select a private identity and must not reach the unentitled
  /// profile. Shared groups never supply the returned application identity.
  String? macOSSignedApplicationIdentifierOrNull() {
    final task = _newMacOSTask();
    try {
      String? readIdentifier(String name) {
        final value = _copyEntitlement(task, name);
        try {
          return value == nullptr ? null : _requiredString(value);
        } finally {
          if (value != nullptr) _cfRelease(value);
        }
      }

      return resolveMacOSSignedApplicationIdentifier(
        readIdentifier: readIdentifier,
        hasKeychainAccessGroups: () {
          final groups = _copyEntitlement(task, 'keychain-access-groups');
          if (groups == nullptr) return false;
          _cfRelease(groups);
          return true;
        },
      );
    } finally {
      _cfRelease(task);
    }
  }

  /// Whether the signed macOS process carries the App Sandbox entitlement.
  bool macOSAppSandboxEnabled() {
    final task = _newMacOSTask();
    try {
      final value = _copyEntitlement(task, 'com.apple.security.app-sandbox');
      if (value == nullptr) return false;
      try {
        if (_cfGetTypeId(value) != _cfBooleanGetTypeId()) {
          throw const AppleHostApiFailure();
        }
        return _cfBooleanGetValue(value) != 0;
      } finally {
        _cfRelease(value);
      }
    } finally {
      _cfRelease(task);
    }
  }

  /// Sets and immediately verifies the public no-backup resource property.
  void setAndVerifyBackupExcluded(Uri directory) {
    final bytes = utf8.encode(directory.toFilePath());
    final buffer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final error = malloc<Pointer<Void>>()..value = nullptr;
    final property = malloc<Pointer<Void>>()..value = nullptr;
    Pointer<Void> url = nullptr;
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      url = _cfUrlCreateFromFileSystemRepresentation(
        nullptr,
        buffer,
        bytes.length,
        1,
      );
      if (url == nullptr) throw const AppleHostApiFailure();
      if (_cfUrlSetResourceProperty(
            url,
            _backupExclusionKey,
            _cfBooleanTrue,
            error,
          ) ==
          0) {
        throw const AppleHostApiFailure();
      }
      if (error.value != nullptr) {
        _cfRelease(error.value);
        error.value = nullptr;
      }
      // CFURL caches resource properties. Clear the just-written value so the
      // verification below must read the filesystem's durable metadata.
      _cfUrlClearResourcePropertyCache(url, _backupExclusionKey);
      if (_cfUrlCopyResourceProperty(
            url,
            _backupExclusionKey,
            property,
            error,
          ) ==
          0) {
        throw const AppleHostApiFailure();
      }
      final actual = property.value;
      if (actual == nullptr ||
          _cfGetTypeId(actual) != _cfBooleanGetTypeId() ||
          _cfBooleanGetValue(actual) == 0) {
        throw const AppleHostApiFailure();
      }
    } finally {
      if (property.value != nullptr) _cfRelease(property.value);
      if (error.value != nullptr) _cfRelease(error.value);
      if (url != nullptr) _cfRelease(url);
      malloc.free(property);
      malloc.free(error);
      malloc.free(buffer);
    }
  }

  Pointer<Void> _newMacOSTask() {
    if (!_bindMacOSEntitlements) throw const AppleHostApiFailure();
    final task = _secTaskCreateFromSelf!(nullptr);
    if (task == nullptr) throw const AppleHostApiFailure();
    return task;
  }

  Pointer<Void> _copyEntitlement(Pointer<Void> task, String name) {
    final nameRef = _createString(name);
    final error = malloc<Pointer<Void>>()..value = nullptr;
    try {
      final value = _secTaskCopyValueForEntitlement!(task, nameRef, error);
      if (error.value != nullptr) {
        _cfRelease(error.value);
        error.value = nullptr;
        if (value != nullptr) _cfRelease(value);
        throw const AppleHostApiFailure();
      }
      return value;
    } finally {
      _cfRelease(nameRef);
      malloc.free(error);
    }
  }

  Pointer<Void> _createString(String value) {
    final bytes = utf8.encode(value);
    final buffer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        buffer.asTypedList(bytes.length).setAll(0, bytes);
      }
      final result = _cfStringCreateWithBytes(
        nullptr,
        buffer,
        bytes.length,
        _utf8Encoding,
        0,
      );
      if (result == nullptr) throw const AppleHostApiFailure();
      return result;
    } finally {
      malloc.free(buffer);
    }
  }

  String _requiredString(Pointer<Void> value) {
    if (value == nullptr || _cfGetTypeId(value) != _cfStringGetTypeId()) {
      throw const AppleHostApiFailure();
    }
    const maximumBytes = 4096;
    final buffer = malloc<Uint8>(maximumBytes);
    try {
      if (_cfStringGetCString(value, buffer, maximumBytes, _utf8Encoding) ==
          0) {
        throw const AppleHostApiFailure();
      }
      var length = 0;
      while (length < maximumBytes && buffer[length] != 0) {
        length += 1;
      }
      if (length == maximumBytes) throw const AppleHostApiFailure();
      return utf8.decode(buffer.asTypedList(length));
    } on FormatException {
      throw const AppleHostApiFailure();
    } finally {
      malloc.free(buffer);
    }
  }
}

/// Resolves the exact signed macOS identity without choosing a shared group.
///
/// The native reader validates entitlement types and bounds before returning
/// strings. These callbacks also allow hermetic qualification tests without
/// loading Apple frameworks. Unreadable evidence propagates as failure.
String? resolveMacOSSignedApplicationIdentifier({
  required String? Function(String name) readIdentifier,
  required bool Function() hasKeychainAccessGroups,
}) {
  final modern = readIdentifier('com.apple.application-identifier');
  final legacy = readIdentifier('application-identifier');
  if ((modern != null && modern.isEmpty) ||
      (legacy != null && legacy.isEmpty) ||
      (modern != null && legacy != null && modern != legacy)) {
    throw const AppleHostApiFailure();
  }
  final identifier = modern ?? legacy;
  if (identifier == null && hasKeychainAccessGroups()) {
    throw const AppleHostApiFailure();
  }
  return identifier;
}

/// Redacted failure at the public Apple host-API boundary.
final class AppleHostApiFailure implements Exception {
  const AppleHostApiFailure();
}

Pointer<Void> _cfConstant(DynamicLibrary library, String name) =>
    library.lookup<Pointer<Void>>(name).value;

const int _utf8Encoding = 0x08000100;
