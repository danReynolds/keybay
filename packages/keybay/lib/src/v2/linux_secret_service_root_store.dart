/// Narrow Secret Service custody seam for the ordinary Linux V2 profile.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import '../errors.dart';
import 'posix_store_files.dart';
import 'store_files.dart';

/// Frozen Secret Service attribute identifying V2 application roots.
const String v2LinuxSecretService = 'dev.keybay.v2.platform-root';

/// Non-secret label shown by credential-store tools.
const String v2LinuxSecretServiceLabel = 'Keybay application store root';

/// Maximum provider value copied into Dart for V2 root processing.
const int v2LinuxSecretServiceMaxRootRecordBytes = 4096;

const Duration _providerTimeout = Duration(seconds: 15);
const Duration _creationLockTimeout = Duration(seconds: 10);
const String _secretServiceName = 'org.freedesktop.secrets';
const String _serviceInterface = 'org.freedesktop.Secret.Service';
const String _collectionInterface = 'org.freedesktop.Secret.Collection';
const String _itemInterface = 'org.freedesktop.Secret.Item';
const String _sessionInterface = 'org.freedesktop.Secret.Session';
const String _lockedError = 'org.freedesktop.Secret.Error.IsLocked';
const String _contentType = 'application/octet-stream';
const DBusObjectPath _servicePath = DBusObjectPath.unchecked(
  '/org/freedesktop/secrets',
);
const DBusObjectPath _noPrompt = DBusObjectPath.root;

/// The fixed-address Secret Service query returned more than one item.
final class LinuxSecretServiceMultipleMatches implements Exception {
  const LinuxSecretServiceMultipleMatches();

  @override
  String toString() => 'LinuxSecretServiceMultipleMatches()';
}

/// A provider operation would require invoking a Secret Service Prompt.
///
/// Keybay never calls Prompt; the caller may arrange provider access and retry.
final class LinuxSecretServiceInteractionRequired implements Exception {
  const LinuxSecretServiceInteractionRequired();

  @override
  String toString() => 'LinuxSecretServiceInteractionRequired()';
}

/// The fixed provider-creation lock remained held through its bounded wait.
final class LinuxSecretServiceProviderBusy implements Exception {
  const LinuxSecretServiceProviderBusy();

  @override
  String toString() => 'LinuxSecretServiceProviderBusy()';
}

/// One uniquely addressed provider record.
///
/// The provider identity is intentionally opaque. [LinuxSecretServiceRootStore.delete]
/// uses this operation-local exact item handle. Reset separately re-reads and
/// revalidates the fixed provider address after preparation before deleting.
abstract interface class LinuxSecretServiceRoot {
  Uint8List get value;
}

/// Exact operations required by the ordinary Linux V2 protector.
abstract interface class LinuxSecretServiceRootStore {
  Future<LinuxSecretServiceRoot?> readUnique(String providerAddress);

  Future<void> createNew(String providerAddress, Uint8List value);

  /// Deletes only the item represented by [root] after an exact re-search.
  ///
  /// Secret Service has no compare-and-delete operation. Re-searching closes
  /// the ordinary stale-path case, but an already-authorized same-user actor
  /// can still replace an item at the same object path between validation and
  /// `Delete`. The protector verifies absence afterwards; this is an honest
  /// denial-of-service boundary, not an application-isolation guarantee.
  Future<void> delete(LinuxSecretServiceRoot root);

  Future<T> withCreationLock<T>(
    String providerAddress,
    Future<T> Function() operation,
  );
}

/// The fixed raw-D-Bus call surface used by the production adapter.
///
/// Destination and authorization flags are absent by design: the production
/// implementation always targets Secret Service and always leaves
/// `ALLOW_INTERACTIVE_AUTHORIZATION` clear.
abstract interface class LinuxSecretServiceDbusClient {
  Future<DBusMethodSuccessResponse> callMethod({
    required DBusObjectPath path,
    required String interface,
    required String name,
    required List<DBusValue> values,
    required DBusSignature replySignature,
  });

  Future<void> close();
}

typedef LinuxSecretServiceDbusClientFactory =
    LinuxSecretServiceDbusClient Function();

/// Production Secret Service transport using exact-signature raw D-Bus calls.
///
/// Each operation owns one fresh session-bus connection and has one total
/// timeout, including connection close. Dart's [Future.timeout] cannot cancel
/// the package's pending method future; at the deadline Keybay initiates
/// [LinuxSecretServiceDbusClient.close] to tear down the socket and ignores any
/// later result. This bounds Keybay's caller but is not a provider-side RPC
/// cancellation guarantee.
///
/// Secrets never cross this API as text or base64. package:dbus necessarily
/// constructs transient immutable D-Bus value/message copies, which Dart
/// cannot reliably zero. Keybay clears the mutable byte snapshots it owns
/// best-effort; this is not a whole-process zeroization claim.
///
/// Keybay never calls `Unlock`, `Prompt`, or `CreateCollection`. A locked item
/// or collection is a typed locked failure. A returned non-root prompt path is
/// a typed interaction-required failure and is never invoked.
final class DbusLinuxSecretServiceRootStore
    implements LinuxSecretServiceRootStore {
  DbusLinuxSecretServiceRootStore({
    required String runtimeDirectory,
    LinuxSecretServiceDbusClientFactory? clientFactory,
    this.timeout = _providerTimeout,
  }) : _runtimeDirectory = _validateAbsoluteDirectory(runtimeDirectory),
       _clientFactory = clientFactory ?? _SystemSecretServiceDbusClient.new;

  final String _runtimeDirectory;
  final LinuxSecretServiceDbusClientFactory _clientFactory;
  final Duration timeout;

  @override
  Future<LinuxSecretServiceRoot?> readUnique(String providerAddress) async {
    final address = _validateProviderAddress(providerAddress);
    Uint8List? unreturnedValue;
    var readLifetimeEnded = false;
    try {
      final result = await _withClient('read', (client) async {
        final paths = await _search(client, address);
        if (paths.count > 1) {
          throw const LinuxSecretServiceMultipleMatches();
        }
        if (paths.locked.length == 1) {
          throw const KeystoreLocked(
            'The Secret Service item exists in a locked collection.',
          );
        }
        if (paths.unlocked.isEmpty) return null;

        return _withPlainSession(client, (session) async {
          final value = await _getSecret(
            client,
            paths.unlocked.single,
            session,
          );
          if (readLifetimeEnded) {
            _clear(value);
            throw const KeystoreOperationFailed(
              'Secret Service read completed after its lifetime ended',
            );
          }
          unreturnedValue = value;
          return _DbusLinuxSecretServiceRoot(
            providerAddress: address,
            path: paths.unlocked.single,
            value: value,
          );
        });
      });
      unreturnedValue = null;
      return result;
    } finally {
      readLifetimeEnded = true;
      final value = unreturnedValue;
      if (value != null) _clear(value);
      unreturnedValue = null;
    }
  }

  @override
  Future<void> createNew(String providerAddress, Uint8List value) async {
    final address = _validateProviderAddress(providerAddress);
    if (value.isEmpty ||
        value.length > v2LinuxSecretServiceMaxRootRecordBytes) {
      throw ArgumentError.value(value.length, 'value', 'invalid root size');
    }
    final snapshot = Uint8List.fromList(value);
    try {
      await _withClient('create', (client) async {
        await _withPlainSession(client, (session) async {
          final collection = await _readDefaultCollection(client);
          final response = await client.callMethod(
            path: collection,
            interface: _collectionInterface,
            name: 'CreateItem',
            values: <DBusValue>[
              _itemProperties(address),
              DBusStruct(<DBusValue>[
                session,
                DBusArray.byte(const <int>[]),
                DBusArray.byte(snapshot),
                const DBusString(_contentType),
              ]),
              const DBusBoolean(false),
            ],
            replySignature: const DBusSignature.unchecked('oo'),
          );
          final item = response.returnValues[0].asObjectPath();
          final prompt = response.returnValues[1].asObjectPath();
          _requireNoPrompt(prompt);
          _requireSecretServiceObject(item, allowRoot: false);
        });
      });
    } finally {
      _clear(snapshot);
    }
  }

  @override
  Future<void> delete(LinuxSecretServiceRoot root) async {
    if (root is! _DbusLinuxSecretServiceRoot) {
      throw ArgumentError.value(root, 'root', 'not owned by this provider');
    }
    await _withClient('delete', (client) async {
      final paths = await _search(client, root.providerAddress);
      if (paths.count > 1) {
        throw const LinuxSecretServiceMultipleMatches();
      }
      if (paths.locked.length == 1) {
        throw const KeystoreLocked(
          'The Secret Service item exists in a locked collection.',
        );
      }
      if (paths.unlocked.length != 1 || paths.unlocked.single != root.path) {
        throw const KeystoreOperationFailed(
          'Secret Service root changed before exact deletion',
        );
      }
      final response = await client.callMethod(
        path: root.path,
        interface: _itemInterface,
        name: 'Delete',
        values: const <DBusValue>[],
        replySignature: const DBusSignature.unchecked('o'),
      );
      _requireNoPrompt(response.returnValues.single.asObjectPath());
    });
  }

  @override
  Future<T> withCreationLock<T>(
    String providerAddress,
    Future<T> Function() operation,
  ) async {
    final address = _validateProviderAddress(providerAddress);
    final String runtimeDirectory;
    try {
      runtimeDirectory = Directory(
        _runtimeDirectory,
      ).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw const KeystoreUnreachable(
        'XDG_RUNTIME_DIR is unavailable for provider coordination',
      );
    }
    try {
      return await PosixStoreFiles.withLinuxSecretServiceCreationLock(
        canonicalRuntimeDirectory: Uri.directory(runtimeDirectory),
        providerAddress: address,
        timeout: _creationLockTimeout,
        operation: operation,
      );
    } on StoreFilesFailure catch (failure) {
      if (failure.code == StoreFilesFailureCode.busy) {
        throw const LinuxSecretServiceProviderBusy();
      }
      throw const KeystoreUnreachable(
        'XDG_RUNTIME_DIR is unavailable for provider coordination',
      );
    }
  }

  Future<T> _withClient<T>(
    String operation,
    Future<T> Function(LinuxSecretServiceDbusClient client) body,
  ) async {
    try {
      final client = _LifetimeBoundSecretServiceDbusClient(_clientFactory());
      final owned = _runWithCleanup(() => body(client), client.close);
      return await owned.timeout(
        timeout,
        onTimeout: () {
          // package:dbus has no per-call cancellation handle. Closing the
          // fresh connection is the narrowest available cancellation action.
          client.endLifetime();
          unawaited(client.close().catchError((Object _) {}));
          throw _LinuxSecretServiceTimeout(operation);
        },
      );
    } on LinuxSecretServiceMultipleMatches {
      rethrow;
    } on LinuxSecretServiceInteractionRequired {
      rethrow;
    } on KeystoreLocked {
      rethrow;
    } on _LinuxSecretServiceTimeout {
      throw KeystoreUnreachable('$operation: Secret Service timed out');
    } on DBusServiceUnknownException {
      throw const KeystoreUnreachable('Secret Service is unavailable');
    } on DBusTimeoutException {
      throw const KeystoreUnreachable('Secret Service timed out');
    } on DBusTimedOutException {
      throw const KeystoreUnreachable('Secret Service timed out');
    } on DBusMethodResponseException catch (error) {
      if (error.errorName == _lockedError) {
        throw const KeystoreLocked('The Secret Service collection is locked.');
      }
      throw KeystoreOperationFailed(
        '$operation: Secret Service returned ${error.errorName}',
      );
    } on DBusClosedException {
      throw const KeystoreUnreachable('Secret Service connection closed');
    } on SocketException {
      throw const KeystoreUnreachable('Secret Service is unavailable');
    } on SecretStoreException {
      rethrow;
    } on Object {
      throw KeystoreOperationFailed('$operation: Secret Service call failed');
    }
  }
}

/// Prevents a timed-out method reply from authorizing the next protocol call.
///
/// A call already handed to D-Bus when the deadline fires remains
/// indeterminate. The checks on both sides of each await ensure that its late
/// reply cannot advance `OpenSession -> ReadAlias -> CreateItem` or
/// `SearchItems -> Delete` after the caller has already received a timeout.
final class _LifetimeBoundSecretServiceDbusClient
    implements LinuxSecretServiceDbusClient {
  _LifetimeBoundSecretServiceDbusClient(this._delegate);

  final LinuxSecretServiceDbusClient _delegate;
  bool _active = true;

  void endLifetime() => _active = false;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    required DBusObjectPath path,
    required String interface,
    required String name,
    required List<DBusValue> values,
    required DBusSignature replySignature,
  }) async {
    if (!_active) throw const _LinuxSecretServiceLifetimeEnded();
    final response = await _delegate.callMethod(
      path: path,
      interface: interface,
      name: name,
      values: values,
      replySignature: replySignature,
    );
    if (!_active) throw const _LinuxSecretServiceLifetimeEnded();
    return response;
  }

  @override
  Future<void> close() {
    endLifetime();
    return _delegate.close();
  }
}

final class _SystemSecretServiceDbusClient
    implements LinuxSecretServiceDbusClient {
  _SystemSecretServiceDbusClient()
    : _client = DBusClient.session(introspectable: false);

  final DBusClient _client;

  @override
  Future<DBusMethodSuccessResponse> callMethod({
    required DBusObjectPath path,
    required String interface,
    required String name,
    required List<DBusValue> values,
    required DBusSignature replySignature,
  }) => _client.callMethod(
    destination: _secretServiceName,
    path: path,
    interface: interface,
    name: name,
    values: values,
    replySignature: replySignature,
    allowInteractiveAuthorization: false,
  );

  @override
  Future<void> close() => _client.close();
}

final class _DbusLinuxSecretServiceRoot implements LinuxSecretServiceRoot {
  _DbusLinuxSecretServiceRoot({
    required this.providerAddress,
    required this.path,
    required this.value,
  });

  final String providerAddress;
  final DBusObjectPath path;

  @override
  final Uint8List value;
}

final class _SearchResult {
  const _SearchResult({required this.unlocked, required this.locked});

  final List<DBusObjectPath> unlocked;
  final List<DBusObjectPath> locked;

  int get count => unlocked.length + locked.length;
}

Future<_SearchResult> _search(
  LinuxSecretServiceDbusClient client,
  String providerAddress,
) async {
  final response = await client.callMethod(
    path: _servicePath,
    interface: _serviceInterface,
    name: 'SearchItems',
    values: <DBusValue>[_addressAttributes(providerAddress)],
    replySignature: const DBusSignature.unchecked('aoao'),
  );
  final unlocked = response.returnValues[0].asObjectPathArray().toList();
  final locked = response.returnValues[1].asObjectPathArray().toList();
  for (final path in <DBusObjectPath>[...unlocked, ...locked]) {
    _requireSecretServiceObject(path, allowRoot: false);
  }
  return _SearchResult(unlocked: unlocked, locked: locked);
}

Future<DBusObjectPath> _openPlainSession(
  LinuxSecretServiceDbusClient client,
) async {
  final response = await client.callMethod(
    path: _servicePath,
    interface: _serviceInterface,
    name: 'OpenSession',
    values: const <DBusValue>[DBusString('plain'), DBusVariant(DBusString(''))],
    replySignature: const DBusSignature.unchecked('vo'),
  );
  final output = response.returnValues[0].asVariant();
  if (output is! DBusString || output.asString().isNotEmpty) {
    throw const KeystoreOperationFailed(
      'Secret Service returned an invalid plain session',
    );
  }
  final session = response.returnValues[1].asObjectPath();
  _requireSecretServiceObject(session, allowRoot: false);
  return session;
}

Future<T> _withPlainSession<T>(
  LinuxSecretServiceDbusClient client,
  Future<T> Function(DBusObjectPath session) operation,
) async {
  final session = await _openPlainSession(client);
  return _runWithCleanup(() => operation(session), () async {
    await client.callMethod(
      path: session,
      interface: _sessionInterface,
      name: 'Close',
      values: const <DBusValue>[],
      replySignature: DBusSignature.empty,
    );
  });
}

Future<T> _runWithCleanup<T>(
  Future<T> Function() operation,
  Future<void> Function() cleanup,
) async {
  late T result;
  Object? primaryFailure;
  StackTrace? primaryStack;
  try {
    result = await operation();
  } on Object catch (error, stackTrace) {
    primaryFailure = error;
    primaryStack = stackTrace;
  }

  try {
    await cleanup();
  } on Object catch (error, stackTrace) {
    primaryFailure ??= error;
    primaryStack ??= stackTrace;
  }

  if (primaryFailure != null) {
    Error.throwWithStackTrace(primaryFailure, primaryStack!);
  }
  return result;
}

Future<Uint8List> _getSecret(
  LinuxSecretServiceDbusClient client,
  DBusObjectPath item,
  DBusObjectPath session,
) async {
  final response = await client.callMethod(
    path: item,
    interface: _itemInterface,
    name: 'GetSecret',
    values: <DBusValue>[session],
    replySignature: const DBusSignature.unchecked('(oayays)'),
  );
  final fields = response.returnValues.single.asStruct();
  if (fields[0].asObjectPath() != session) {
    throw const KeystoreOperationFailed(
      'Secret Service returned a secret for another session',
    );
  }
  if (fields[1].asByteArray().isNotEmpty) {
    throw const KeystoreOperationFailed(
      'Secret Service returned parameters for a plain session',
    );
  }
  // Providers such as gnome-keyring normalize this metadata even though the
  // typed byte array is preserved exactly. Parse the fixed-signature reply
  // shape, but
  // do not give content_type authority over Keybay's already domain-bound,
  // authenticated root record.
  fields[3].asString();
  final bytes = fields[2].asByteArray();
  if (bytes.length > v2LinuxSecretServiceMaxRootRecordBytes) {
    throw const KeystoreOperationFailed(
      'Secret Service root exceeds the V2 bound',
    );
  }
  return Uint8List.fromList(bytes.toList(growable: false));
}

Future<DBusObjectPath> _readDefaultCollection(
  LinuxSecretServiceDbusClient client,
) async {
  final response = await client.callMethod(
    path: _servicePath,
    interface: _serviceInterface,
    name: 'ReadAlias',
    values: const <DBusValue>[DBusString('default')],
    replySignature: const DBusSignature.unchecked('o'),
  );
  final collection = response.returnValues.single.asObjectPath();
  if (collection == DBusObjectPath.root) {
    // Creating a default collection is intentionally outside Keybay's API.
    throw const KeystoreUnreachable('Secret Service has no default collection');
  }
  _requireSecretServiceObject(collection, allowRoot: false);
  return collection;
}

DBusDict _addressAttributes(String providerAddress) =>
    DBusDict(DBusSignature.string, DBusSignature.string, <DBusValue, DBusValue>{
      const DBusString('service'): const DBusString(v2LinuxSecretService),
      const DBusString('account'): DBusString(providerAddress),
    });

DBusDict _itemProperties(String providerAddress) =>
    DBusDict.stringVariant(<String, DBusValue>{
      'org.freedesktop.Secret.Item.Label': const DBusString(
        v2LinuxSecretServiceLabel,
      ),
      'org.freedesktop.Secret.Item.Attributes': _addressAttributes(
        providerAddress,
      ),
    });

void _requireNoPrompt(DBusObjectPath prompt) {
  if (prompt != _noPrompt) {
    throw const LinuxSecretServiceInteractionRequired();
  }
}

void _requireSecretServiceObject(
  DBusObjectPath path, {
  required bool allowRoot,
}) {
  if ((!allowRoot && path == DBusObjectPath.root) ||
      !path.value.startsWith('/org/freedesktop/secrets/')) {
    throw const KeystoreOperationFailed(
      'Secret Service returned an invalid object path',
    );
  }
}

String _validateProviderAddress(String value) {
  if (!_providerAddressGrammar.hasMatch(value)) {
    throw ArgumentError.value('<redacted>', 'providerAddress', 'invalid');
  }
  return value;
}

String _validateAbsoluteDirectory(String value) {
  if (value.isEmpty || !value.startsWith('/') || value.contains('\u0000')) {
    throw ArgumentError.value('<redacted>', 'runtimeDirectory', 'invalid');
  }
  return value.length > 1 && value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
}

final RegExp _providerAddressGrammar = RegExp(r'^[A-Za-z0-9_-]{43}$');

final class _LinuxSecretServiceTimeout implements Exception {
  const _LinuxSecretServiceTimeout(this.operation);

  final String operation;
}

final class _LinuxSecretServiceLifetimeEnded implements Exception {
  const _LinuxSecretServiceLifetimeEnded();
}

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
