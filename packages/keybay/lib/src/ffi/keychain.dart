/// Narrow Apple Keychain binding for V2 application-store roots.
///
/// Direct Security.framework FFI — no subprocess, no text protocol; secrets
/// move as `CFData`. This is the package's most delicate FFI: CoreFoundation is
/// manually reference-counted, so every `*Create*` is paired with `CFRelease`.
///
/// The two storage modes are fully qualified before construction:
/// - [AppleKeychainApi.fileKeychainAt] pins every operation to the effective
///   account's explicit login-Keychain file.
/// - [AppleKeychainApi.v2DataProtection] pins every operation to one exact,
///   already-qualified signed application-identifier group and fixes new items
///   to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
///
/// Both modes create non-synchronizing items. Reads are bounded before any Dart
/// allocation; mutation is limited to atomic add-if-absent and exact delete.
/// This binding never enumerates or clears a service and never upserts a root.
///
/// Symbol loading: macOS `dlopen`s the frameworks by absolute path (a plain
/// Dart VM links neither); on iOS every app process already has
/// CoreFoundation/Security loaded, so symbols come from the process image.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../errors.dart';

// --- OSStatus values we branch on -------------------------------------------
const int _errSecSuccess = 0;
const int _errSecItemNotFound = -25300;
const int _errSecDuplicateItem = -25299;
const int _errSecAuthFailed = -25293;
const int _errSecNoSuchKeychain = -25294;
const int _errSecInvalidKeychain = -25295;
const int _errSecInteractionNotAllowed = -25308;
const int _errSecNotAvailable = -25291;
const int _errSecNoDefaultKeychain = -25307;
const int _errSecInteractionRequired = -25315;
const int _errSecMissingEntitlement = -34018;

const int _kCFStringEncodingUTF8 = 0x08000100;

typedef _CFTypeRef = Pointer<Void>;
final _CFTypeRef _nullRef = nullptr;

final Finalizer<_RetainedCFRef> _retainedCFRefFinalizer =
    Finalizer<_RetainedCFRef>((resource) => resource.release(resource.ref));

final class _RetainedCFRef {
  const _RetainedCFRef(this.ref, this.release);

  final Pointer<Void> ref;
  // `lookupFunction` returns a native trampoline; it does not capture the
  // AppleKeychainApi instance and keep this finalizer's target alive.
  final void Function(Pointer<Void>) release;
}

/// The real V2 Apple binding (macOS + iOS).
final class AppleKeychainApi {
  /// The classic file-based Keychain restricted to one explicit absolute path
  /// instead of the user's mutable default or configurable search list.
  AppleKeychainApi.fileKeychainAt(String path)
    : this._(
        fixedFileKeychainPath: _validateKeychainPath(path),
        exactDataProtectionAccessGroup: null,
      );

  /// The V2 Data Protection Keychain root store.
  ///
  /// [exactApplicationIdentifierAccessGroup] is supplied only by a qualified
  /// Apple host profile after it has established the signed app's exact
  /// application-identifier group. This factory cannot select a shared group
  /// and does not inspect entitlements, including on iOS.
  AppleKeychainApi.v2DataProtection({
    required String exactApplicationIdentifierAccessGroup,
  }) : this._(
         fixedFileKeychainPath: null,
         exactDataProtectionAccessGroup: _validateExactAccessGroup(
           exactApplicationIdentifierAccessGroup,
         ),
       );

  AppleKeychainApi._({
    required String? fixedFileKeychainPath,
    required String? exactDataProtectionAccessGroup,
  }) : assert(
         (fixedFileKeychainPath == null) !=
             (exactDataProtectionAccessGroup == null),
       ),
       _fixedFileKeychainPath = fixedFileKeychainPath,
       _exactDataProtectionAccessGroup = exactDataProtectionAccessGroup,
       // iOS: every app process already has these frameworks loaded (UIKit's
       // dependency chain), and absolute-path dlopen is the macOS shape —
       // resolve from the process image instead. macOS: a plain Dart VM
       // links neither framework, so dlopen by absolute path.
       _cf = Platform.isIOS
           ? DynamicLibrary.process()
           : DynamicLibrary.open(
               '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',
             ),
       _sec = Platform.isIOS
           ? DynamicLibrary.process()
           : DynamicLibrary.open(
               '/System/Library/Frameworks/Security.framework/Security',
             ) {
    _bind();
  }

  /// When true, target the Data Protection Keychain instead of classic
  /// file-based Keychains (see the constructors and the library doc comment).
  bool get _dataProtection => _exactDataProtectionAccessGroup != null;

  /// The exact file-Keychain path, or null for Data Protection Keychain mode.
  final String? _fixedFileKeychainPath;

  /// The exact group selected by the V2 host profile. Null in file-Keychain
  /// mode.
  final String? _exactDataProtectionAccessGroup;

  _CFTypeRef? _fixedFileKeychain;

  final DynamicLibrary _cf;
  final DynamicLibrary _sec;

  // CoreFoundation
  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    int,
  )
  _cfStringCreateWithBytes;
  late final Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)
  _cfDataCreate;
  late final int Function(Pointer<Void>) _cfDataGetLength;
  late final Pointer<Uint8> Function(Pointer<Void>) _cfDataGetBytePtr;
  late final Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Pointer<Void>>,
    Pointer<Pointer<Void>>,
    int,
    Pointer<Void>,
    Pointer<Void>,
  )
  _cfDictionaryCreate;
  Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Pointer<Void>>,
    int,
    Pointer<Void>,
  )?
  _cfArrayCreate;
  late final void Function(Pointer<Void>) _cfRelease;

  // Security
  late final int Function(Pointer<Void>, Pointer<Pointer<Void>>) _secItemAdd;
  late final int Function(Pointer<Void>, Pointer<Pointer<Void>>)
  _secItemCopyMatching;
  late final int Function(Pointer<Void>) _secItemDelete;
  int Function(Pointer<Utf8>, Pointer<Pointer<Void>>)? _secKeychainOpen;

  // Constant CFStringRef / CFBooleanRef symbols.
  late final Pointer<Void> _keyCallbacks;
  late final Pointer<Void> _valueCallbacks;
  Pointer<Void>? _arrayCallbacks;
  late final _CFTypeRef _kSecClass,
      _kSecClassGenericPassword,
      _kSecAttrService,
      _kSecAttrAccount,
      _kSecAttrAccessGroup,
      _kSecAttrLabel,
      _kSecValueData,
      _kSecReturnData,
      _kSecReturnAttributes,
      _kSecMatchLimit,
      _kSecMatchLimitOne,
      _kSecAttrSynchronizable,
      _kSecAttrAccessible,
      _kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      _kSecUseDataProtectionKeychain,
      _kSecUseAuthenticationUI,
      _kSecUseAuthenticationUIFail,
      _kCFBooleanTrue,
      _kCFBooleanFalse;
  _CFTypeRef? _kSecUseKeychain, _kSecMatchSearchList;

  void _bind() {
    _cfStringCreateWithBytes = _cf
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
    _cfDataCreate = _cf
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, IntPtr),
          Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int)
        >('CFDataCreate');
    _cfDataGetLength = _cf
        .lookupFunction<
          IntPtr Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CFDataGetLength');
    _cfDataGetBytePtr = _cf
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>),
          Pointer<Uint8> Function(Pointer<Void>)
        >('CFDataGetBytePtr');
    _cfDictionaryCreate = _cf
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            IntPtr,
            Pointer<Void>,
            Pointer<Void>,
          ),
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Pointer<Void>>,
            Pointer<Pointer<Void>>,
            int,
            Pointer<Void>,
            Pointer<Void>,
          )
        >('CFDictionaryCreate');
    if (_fixedFileKeychainPath != null) {
      _cfArrayCreate = _cf
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Pointer<Void>>,
              IntPtr,
              Pointer<Void>,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Void>,
            )
          >('CFArrayCreate');
    }
    _cfRelease = _cf
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('CFRelease');
    _secItemAdd = _sec
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(Pointer<Void>, Pointer<Pointer<Void>>)
        >('SecItemAdd');
    _secItemCopyMatching = _sec
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(Pointer<Void>, Pointer<Pointer<Void>>)
        >('SecItemCopyMatching');
    _secItemDelete = _sec
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('SecItemDelete');
    if (_fixedFileKeychainPath != null) {
      _secKeychainOpen = _sec
          .lookupFunction<
            Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>),
            int Function(Pointer<Utf8>, Pointer<Pointer<Void>>)
          >('SecKeychainOpen');
    }
    _keyCallbacks = _cf.lookup<Void>('kCFTypeDictionaryKeyCallBacks');
    _valueCallbacks = _cf.lookup<Void>('kCFTypeDictionaryValueCallBacks');
    if (_fixedFileKeychainPath != null) {
      _arrayCallbacks = _cf.lookup<Void>('kCFTypeArrayCallBacks');
    }
    _kCFBooleanTrue = _cfConst(_cf, 'kCFBooleanTrue');
    _kCFBooleanFalse = _cfConst(_cf, 'kCFBooleanFalse');
    _kSecClass = _cfConst(_sec, 'kSecClass');
    _kSecClassGenericPassword = _cfConst(_sec, 'kSecClassGenericPassword');
    _kSecAttrService = _cfConst(_sec, 'kSecAttrService');
    _kSecAttrAccount = _cfConst(_sec, 'kSecAttrAccount');
    _kSecAttrAccessGroup = _cfConst(_sec, 'kSecAttrAccessGroup');
    _kSecAttrLabel = _cfConst(_sec, 'kSecAttrLabel');
    _kSecValueData = _cfConst(_sec, 'kSecValueData');
    _kSecReturnData = _cfConst(_sec, 'kSecReturnData');
    _kSecReturnAttributes = _cfConst(_sec, 'kSecReturnAttributes');
    _kSecMatchLimit = _cfConst(_sec, 'kSecMatchLimit');
    _kSecMatchLimitOne = _cfConst(_sec, 'kSecMatchLimitOne');
    _kSecAttrSynchronizable = _cfConst(_sec, 'kSecAttrSynchronizable');
    _kSecAttrAccessible = _cfConst(_sec, 'kSecAttrAccessible');
    _kSecAttrAccessibleWhenUnlockedThisDeviceOnly = _cfConst(
      _sec,
      'kSecAttrAccessibleWhenUnlockedThisDeviceOnly',
    );
    _kSecUseDataProtectionKeychain = _cfConst(
      _sec,
      'kSecUseDataProtectionKeychain',
    );
    _kSecUseAuthenticationUI = _cfConst(_sec, 'kSecUseAuthenticationUI');
    _kSecUseAuthenticationUIFail = _cfConst(
      _sec,
      'kSecUseAuthenticationUIFail',
    );
    if (_fixedFileKeychainPath != null) {
      _kSecUseKeychain = _cfConst(_sec, 'kSecUseKeychain');
      _kSecMatchSearchList = _cfConst(_sec, 'kSecMatchSearchList');
      _pinFileKeychain(_fixedFileKeychainPath);
    }
  }

  void _pinFileKeychain(String path) {
    final pathPointer = path.toNativeUtf8();
    final out = malloc<Pointer<Void>>()..value = nullptr;
    try {
      final status = _secKeychainOpen!(pathPointer, out);
      if (status != _errSecSuccess) {
        _fail(status, 'fixed file Keychain');
      }
      final keychain = out.value;
      if (keychain == nullptr) {
        throw const KeystoreUnreachable('fixed file Keychain is absent');
      }
      _fixedFileKeychain = keychain;
      _retainedCFRefFinalizer.attach(
        this,
        _RetainedCFRef(keychain, _cfRelease),
        detach: this,
      );
    } finally {
      malloc.free(out);
      malloc.free(pathPointer);
    }
  }

  /// V2 DP roots are device-bound and available only while the device is
  /// unlocked. File-Keychain roots use the Keychain file's own ACL policy.
  List<(Pointer<Void>, Pointer<Void>)> get _accessibilityPairs =>
      _dataProtection
      ? [(_kSecAttrAccessible, _kSecAttrAccessibleWhenUnlockedThisDeviceOnly)]
      : const [];

  List<(Pointer<Void>, Pointer<Void>)> _accessGroupPairs(
    List<Pointer<Void>> refs,
  ) {
    if (!_dataProtection) return const [];
    final exact = _exactDataProtectionAccessGroup!;
    final group = _cfString(exact)..let(refs.add);
    return [(_kSecAttrAccessGroup, group)];
  }

  /// The Data Protection Keychain enforces this per-call UI restriction.
  /// Classic file Keychains ignore it and can prompt; their protector must
  /// reject interaction-forbidden acquisitions before reaching this binding.
  /// A process-global SecKeychainSetUserInteractionAllowed toggle would affect
  /// unrelated callers and cannot provide a safe per-operation policy.
  List<(Pointer<Void>, Pointer<Void>)> get _uiPairs => _dataProtection
      ? [(_kSecUseAuthenticationUI, _kSecUseAuthenticationUIFail)]
      : const [];

  /// The `kSecUseDataProtectionKeychain` value for the selected mode. Set
  /// explicitly (never omitted) so the target keychain is deterministic —
  /// modern macOS routes a bare query to the DP keychain by default, which
  /// would silently diverge from our intent.
  _CFTypeRef get _dpValue =>
      _dataProtection ? _kCFBooleanTrue : _kCFBooleanFalse;

  /// Selects the DP or ordinary file-Keychain family when no exact file
  /// Keychain is already selected. Exact file selectors are complete, so the
  /// pinned mode omits this redundant family selector.
  List<(Pointer<Void>, Pointer<Void>)> get _keychainFamilyPairs =>
      _fixedFileKeychainPath == null
      ? [(_kSecUseDataProtectionKeychain, _dpValue)]
      : const [];

  // A CFStringRef/CFBooleanRef exported constant: read the pointer stored at the
  // symbol's address.
  _CFTypeRef _cfConst(DynamicLibrary lib, String name) =>
      lib.lookup<Pointer<Void>>(name).value;

  _CFTypeRef _cfString(String s) {
    final bytes = Uint8List.fromList(utf8.encode(s));
    final buf = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    try {
      if (bytes.isNotEmpty) {
        buf.asTypedList(bytes.length).setAll(0, bytes);
      }
      final ref = _cfStringCreateWithBytes(
        _nullRef,
        buf,
        bytes.length,
        _kCFStringEncodingUTF8,
        0,
      );
      if (ref == nullptr) {
        throw const KeystoreOperationFailed('CFString create failed');
      }
      return ref;
    } finally {
      malloc.free(buf);
    }
  }

  _CFTypeRef _cfData(Uint8List v) {
    final buf = malloc<Uint8>(v.isEmpty ? 1 : v.length);
    try {
      if (v.isNotEmpty) {
        buf.asTypedList(v.length).setAll(0, v);
      }
      final ref = _cfDataCreate(_nullRef, buf, v.length);
      if (ref == nullptr) {
        throw const KeystoreOperationFailed('CFData create failed');
      }
      return ref;
    } finally {
      // Scrub the staging copy of the secret before returning it to the
      // allocator — native memory, unlike the Dart heap, can be zeroed.
      // (CFDataCreate has already taken its own copy.)
      if (v.isNotEmpty) {
        buf.asTypedList(v.length).fillRange(0, v.length, 0);
      }
      malloc.free(buf);
    }
  }

  /// Builds a CFDictionary from [pairs], returning the dict plus every CF ref
  /// that must be released afterwards (the dict retains its own copies).
  ({Pointer<Void> dict, List<Pointer<Void>> owned}) _dict(
    List<(Pointer<Void>, Pointer<Void>)> pairs,
  ) {
    final n = pairs.length;
    final keys = malloc<Pointer<Void>>(n);
    final values = malloc<Pointer<Void>>(n);
    try {
      for (var i = 0; i < n; i++) {
        keys[i] = pairs[i].$1;
        values[i] = pairs[i].$2;
      }
      final dict = _cfDictionaryCreate(
        _nullRef,
        keys,
        values,
        n,
        _keyCallbacks,
        _valueCallbacks,
      );
      if (dict == nullptr) {
        throw const KeystoreOperationFailed('CFDictionary create failed');
      }
      return (dict: dict, owned: [dict]);
    } finally {
      malloc.free(keys);
      malloc.free(values);
    }
  }

  /// Pins one V2 root operation to the effective account's explicit login
  /// Keychain. Creation uses `kSecUseKeychain`; queries and deletion use a
  /// one-element `kSecMatchSearchList`.
  List<(Pointer<Void>, Pointer<Void>)> _fixedFileKeychainPairs(
    List<Pointer<Void>> refs, {
    required bool forAdd,
  }) {
    if (_fixedFileKeychainPath == null) return const [];

    final keychain = _fixedFileKeychain!;
    if (forAdd) {
      return [(_kSecUseKeychain!, keychain)];
    }

    final values = malloc<Pointer<Void>>(1)..[0] = keychain;
    try {
      final searchList = _cfArrayCreate!(_nullRef, values, 1, _arrayCallbacks!);
      if (searchList == nullptr) {
        throw const KeystoreOperationFailed(
          'fixed file Keychain search-list creation failed',
        );
      }
      refs.add(searchList);
      return [(_kSecMatchSearchList!, searchList)];
    } finally {
      malloc.free(values);
    }
  }

  void _releaseAll(Iterable<Pointer<Void>> refs) {
    for (final r in refs) {
      if (r != nullptr) {
        _cfRelease(r);
      }
    }
  }

  Never _fail(int status, String op) {
    switch (status) {
      case _errSecInteractionNotAllowed:
        throw KeystoreLocked('$op: keychain locked / interaction not allowed');
      case _errSecNotAvailable ||
          _errSecNoSuchKeychain ||
          _errSecInvalidKeychain ||
          _errSecNoDefaultKeychain:
        throw KeystoreUnreachable('$op: keychain not available');
      case _errSecMissingEntitlement:
        throw KeystoreUnreachable(
          '$op: the Data Protection keychain requires a keychain-access-groups '
          'entitlement (Xcode "Keychain Sharing") authorized by a provisioning '
          'profile; it is unavailable to unsigned or unentitled processes '
          '(use a qualified file-Keychain profile instead)',
        );
      case _errSecAuthFailed:
        throw KeystoreOperationFailed(
          '$op: authorization failed',
          status: status,
        );
      case _errSecInteractionRequired:
        throw KeystoreOperationFailed(
          '$op: interaction required',
          status: status,
        );
      default:
        throw KeystoreOperationFailed(
          '$op failed (OSStatus $status)',
          status: status,
        );
    }
  }

  /// Reads one exact item and rejects an oversized value before allocating its
  /// Dart representation.
  Future<Uint8List?> getBounded(
    String service,
    String account, {
    required int maxValueBytes,
  }) async {
    if (maxValueBytes < 0) {
      throw ArgumentError.value(maxValueBytes, 'maxValueBytes');
    }
    final refs = <Pointer<Void>>[];
    try {
      final svc = _cfString(service)..let(refs.add);
      final acct = _cfString(account)..let(refs.add);
      final q = _dict([
        (_kSecClass, _kSecClassGenericPassword),
        (_kSecAttrService, svc),
        (_kSecAttrAccount, acct),
        ..._accessGroupPairs(refs),
        ..._fixedFileKeychainPairs(refs, forAdd: false),
        ..._keychainFamilyPairs,
        (_kSecReturnData, _kCFBooleanTrue),
        (_kSecMatchLimit, _kSecMatchLimitOne),
        ..._uiPairs,
      ]);
      refs.addAll(q.owned);
      final out = malloc<Pointer<Void>>();
      try {
        final status = _secItemCopyMatching(q.dict, out);
        if (status == _errSecItemNotFound) {
          return null;
        }
        if (status != _errSecSuccess) {
          _fail(status, 'get');
        }
        final data = out.value;
        // A stored 0-byte value is present, not absent: some keychains return
        // errSecSuccess with a null data ref (rather than an empty CFData) for
        // it. Treat that as the empty value, never a NULL-deref into CFData.
        if (data == nullptr) {
          return Uint8List(0);
        }
        refs.add(data);
        return _copyDataBounded(data, maximum: maxValueBytes);
      } finally {
        malloc.free(out);
      }
    } finally {
      _releaseAll(refs);
    }
  }

  Future<bool> exists(String service, String account) async {
    final refs = <Pointer<Void>>[];
    try {
      final svc = _cfString(service)..let(refs.add);
      final acct = _cfString(account)..let(refs.add);
      final q = _dict([
        (_kSecClass, _kSecClassGenericPassword),
        (_kSecAttrService, svc),
        (_kSecAttrAccount, acct),
        ..._accessGroupPairs(refs),
        ..._fixedFileKeychainPairs(refs, forAdd: false),
        ..._keychainFamilyPairs,
        // Attributes only — never kSecReturnData — so a presence check never
        // pulls the value out of the keychain (nor decrypts it via the Secure
        // Enclave on the DP keychain).
        (_kSecReturnAttributes, _kCFBooleanTrue),
        (_kSecMatchLimit, _kSecMatchLimitOne),
        ..._uiPairs,
      ]);
      refs.addAll(q.owned);
      final out = malloc<Pointer<Void>>();
      try {
        final status = _secItemCopyMatching(q.dict, out);
        if (status == _errSecItemNotFound) {
          return false;
        }
        if (status != _errSecSuccess) {
          _fail(status, 'exists');
        }
        // Success hands back an owned attributes dict (CopyMatching); release
        // it with the rest. Its contents are non-secret and go unread.
        if (out.value != nullptr) {
          refs.add(out.value);
        }
        return true;
      } finally {
        malloc.free(out);
      }
    } finally {
      _releaseAll(refs);
    }
  }

  Future<bool> addIfAbsent(
    String service,
    String account,
    Uint8List value, {
    required String label,
  }) async {
    final refs = <Pointer<Void>>[];
    try {
      final svc = _cfString(service)..let(refs.add);
      final acct = _cfString(account)..let(refs.add);
      final data = _cfData(value)..let(refs.add);
      final labelRef = _cfString(label)..let(refs.add);
      final add = _dict([
        (_kSecClass, _kSecClassGenericPassword),
        (_kSecAttrService, svc),
        (_kSecAttrAccount, acct),
        ..._accessGroupPairs(refs),
        ..._fixedFileKeychainPairs(refs, forAdd: true),
        (_kSecValueData, data),
        ..._keychainFamilyPairs,
        (_kSecAttrSynchronizable, _kCFBooleanFalse),
        (_kSecAttrLabel, labelRef),
        ..._accessibilityPairs,
        ..._uiPairs,
      ]);
      refs.addAll(add.owned);
      final status = _secItemAdd(add.dict, nullptr);
      if (status == _errSecSuccess) return true;
      if (status == _errSecDuplicateItem) return false;
      _fail(status, 'addIfAbsent');
    } finally {
      _releaseAll(refs);
    }
  }

  Future<void> delete(String service, String account) async {
    final refs = <Pointer<Void>>[];
    try {
      final svc = _cfString(service)..let(refs.add);
      final acct = _cfString(account)..let(refs.add);
      final q = _dict([
        (_kSecClass, _kSecClassGenericPassword),
        (_kSecAttrService, svc),
        (_kSecAttrAccount, acct),
        ..._accessGroupPairs(refs),
        ..._fixedFileKeychainPairs(refs, forAdd: false),
        ..._keychainFamilyPairs,
        ..._uiPairs,
      ]);
      refs.addAll(q.owned);
      final status = _secItemDelete(q.dict);
      if (status != _errSecSuccess && status != _errSecItemNotFound) {
        _fail(status, 'delete');
      }
    } finally {
      _releaseAll(refs);
    }
  }

  Uint8List _copyDataBounded(Pointer<Void> data, {required int maximum}) {
    final length = _cfDataGetLength(data);
    if (length < 0 || length > maximum) {
      throw const KeystoreOperationFailed(
        'Keychain value has an invalid length',
      );
    }
    final pointer = _cfDataGetBytePtr(data);
    if (length != 0 && pointer == nullptr) {
      throw const KeystoreOperationFailed('Keychain value has no bytes');
    }
    return length == 0
        ? Uint8List(0)
        : Uint8List.fromList(pointer.asTypedList(length));
  }
}

String _validateKeychainPath(String path) {
  final uri = Uri.file(path);
  if (!path.startsWith('/') ||
      path.contains('\u0000') ||
      path.length > 4096 ||
      uri.normalizePath().toFilePath() != path) {
    throw ArgumentError.value(
      '<redacted>',
      'path',
      'must be a normalized absolute file path',
    );
  }
  return path;
}

String _validateExactAccessGroup(String group) {
  final bytes = utf8.encode(group);
  if (bytes.isEmpty ||
      bytes.length > 512 ||
      !_exactAccessGroupGrammar.hasMatch(group) ||
      group.endsWith('.') ||
      group.contains('..')) {
    throw ArgumentError.value(
      '<redacted>',
      'exactApplicationIdentifierAccessGroup',
      'must be one bounded, non-wildcard signed application identifier',
    );
  }
  return group;
}

final RegExp _exactAccessGroupGrammar = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9.-]{0,511}$',
);

// Terse `..let(list.add)` for tracking CF refs to release.
extension _Let<T> on T {
  void let(void Function(T) f) => f(this);
}
