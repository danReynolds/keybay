/// Bounded XDG Secret Portal transport for the Flatpak V2 profile.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';

import 'platform_protector.dart';
import 'portal_secret_pipe.dart';

const String _portalName = 'org.freedesktop.portal.Desktop';
const String _secretInterface = 'org.freedesktop.portal.Secret';
const String _requestInterface = 'org.freedesktop.portal.Request';
const DBusObjectPath _portalPath = DBusObjectPath.unchecked(
  '/org/freedesktop/portal/desktop',
);

/// Resource bound for the opaque portal secret, before key derivation.
const int linuxSecretPortalMaxSecretBytes = 4096;

/// Retrieval of the portal-owned, reusable application secret.
abstract interface class LinuxSecretPortal {
  /// Returns nonempty, bounded, caller-owned bytes. The caller must clear them.
  ///
  /// Secret Portal has no no-UI option. Forbidden interaction must fail before
  /// connecting or invoking the portal. No continuation tokens are supported.
  Future<Uint8List> retrieveSecret({required PlatformInteraction interaction});
}

/// Operation-local transport seam; production always addresses Secret Portal.
///
/// The pipe remains owned by the caller. Implementations transfer its writable
/// descriptor without closing that local endpoint. Subscriptions must be
/// installed and acknowledged before [subscribeResponse] completes.
abstract interface class LinuxSecretPortalConnection {
  /// Exercises the production adapter against a disposable test message bus.
  /// This internal seam does not alter the fixed portal destination or calls.
  factory LinuxSecretPortalConnection.withDbusClient(DBusClient client) =
      _SystemPortalConnection.withDbusClient;

  String get uniqueName;

  Future<String?> resolveOwner({required bool activate});

  Future<void> subscribeResponse({
    required DBusObjectPath path,
    required void Function(DBusSignal) onResponse,
    required void Function() onError,
  });

  Future<DBusMethodSuccessResponse> retrieve({
    required String owner,
    required String handleToken,
    required RandomAccessFile output,
  });

  /// Sends Close without waiting for a provider reply.
  Future<void> closeRequest({
    required String owner,
    required DBusObjectPath path,
  });

  Future<void> close();
}

typedef LinuxSecretPortalConnectionFactory =
    LinuxSecretPortalConnection Function();

/// Secret v1 using an anonymous Unix pipe and one fresh D-Bus connection.
///
/// One absolute timeout covers connection, request, pipe EOF, owner validation,
/// and cleanup. Timeout initiates Request.Close and connection/pipe cleanup;
/// late completions cannot return bytes or start another protocol step. Dart
/// and package:dbus cannot forcibly cancel every pending native I/O future, so
/// the deadline bounds the caller, not a hostile provider's resource lifetime.
///
/// Only the modern, handle_token-derived Request path is supported. A token in
/// Response results is rejected before any secret is returned. Secret bytes
/// never appear in D-Bus values, diagnostics, or exception messages.
final class DbusLinuxSecretPortal implements LinuxSecretPortal {
  DbusLinuxSecretPortal({
    LinuxSecretPortalConnectionFactory? clientFactory,
    this.timeout = const Duration(seconds: 60),
  }) : _clientFactory = clientFactory ?? _SystemPortalConnection.new {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  final LinuxSecretPortalConnectionFactory _clientFactory;
  final Duration timeout;

  @override
  Future<Uint8List> retrieveSecret({
    required PlatformInteraction interaction,
  }) async {
    if (interaction == PlatformInteraction.forbidden) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.interactionRequired,
      );
    }
    try {
      return await _PortalRetrieval(_clientFactory()).run(timeout);
    } catch (error) {
      throw _redact(error);
    }
  }
}

final class _PortalRetrieval {
  _PortalRetrieval(this.client);

  final LinuxSecretPortalConnection client;
  final Uint8List _bytes = Uint8List(linuxSecretPortalMaxSecretBytes);
  final Completer<void> _response = Completer<void>();
  final Completer<void> _endOfPipe = Completer<void>();
  Timer? _reader;
  PortalSecretPipe? _pipe;
  String? _owner;
  DBusObjectPath? _path;
  Future<void>? _cleanupFuture;
  PlatformProtectorFailure? _terminalFailure;
  var _length = 0;
  var _active = true;
  var _requestStarted = false;
  var _responseReceived = false;

  Future<Uint8List> run(Duration timeout) async {
    // Attach error handlers before either channel can complete independently.
    final channels = Future.wait<void>([
      _response.future,
      _endOfPipe.future,
    ], eagerError: true);
    channels.ignore();
    try {
      return await _retrieve(channels).timeout(timeout);
    } finally {
      _active = false;
      _bytes.fillRange(0, _bytes.length, 0);
      _cleanup(abort: true).ignore();
    }
  }

  Future<Uint8List> _retrieve(Future<void> channels) async {
    _owner = await client.resolveOwner(activate: true);
    _checkActive();
    if (!_isUniqueName(_owner) || !_isUniqueName(client.uniqueName)) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }
    final random = Random.secure();
    final token =
        'keybay_${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final sender = client.uniqueName.substring(1).replaceAll('.', '_');
    _path = DBusObjectPath('${_portalPath.value}/request/$sender/$token');
    await client.subscribeResponse(
      path: _path!,
      onResponse: _onResponse,
      onError: _failResponse,
    );
    _checkActive();
    _pipe = PortalSecretPipe();
    _reader = Timer.periodic(const Duration(milliseconds: 2), (_) {
      try {
        final bytes = _pipe!.readAvailable();
        if (bytes == null) return;
        if (bytes.isNotEmpty) {
          _onBytes(bytes);
        } else {
          _reader?.cancel();
          if (!_endOfPipe.isCompleted) {
            if (_length == 0) {
              _failPipe();
            } else {
              _endOfPipe.complete();
            }
          }
        }
      } on Object {
        _reader?.cancel();
        _failPipe();
      }
    });
    _requestStarted = true;
    await Future.wait<void>([
      _retrieveHandle(token),
      channels,
    ], eagerError: true);
    _checkActive();
    if (await client.resolveOwner(activate: false) != _owner) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.invalidated,
      );
    }
    _checkActive();
    await _cleanup(abort: false);
    _checkActive();
    return _bytes.sublist(0, _length);
  }

  Future<void> _retrieveHandle(String token) async {
    final reply = await client.retrieve(
      owner: _owner!,
      handleToken: token,
      output: _pipe!.output,
    );
    _checkActive();
    // The method reply means the descriptor was transferred. Close our copy
    // so provider closure becomes EOF; retain the read side until validation.
    await _pipe!.closeWriter();
    _checkActive();
    if (reply.signature != DBusSignature('o') ||
        reply.returnValues.single != _path) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
  }

  void _onResponse(DBusSignal signal) {
    if (!_active || _response.isCompleted) return;
    if (signal.sender != _owner ||
        signal.path != _path ||
        signal.interface != _requestInterface ||
        signal.name != 'Response') {
      return;
    }
    if (signal.signature != DBusSignature('ua{sv}')) {
      _failResponse();
      return;
    }
    final code = signal.values.first.asUint32();
    _responseReceived = code <= 2;
    final results = signal.values[1].asStringVariantDict();
    if (results.containsKey('token')) {
      _failResponse(PlatformProtectorFailureCode.unavailable);
    } else if (code == 0) {
      _response.complete();
    } else {
      _failResponse(
        code == 1
            ? PlatformProtectorFailureCode.interactionRequired
            : PlatformProtectorFailureCode.operationFailed,
      );
    }
  }

  void _onBytes(List<int> chunk) {
    try {
      if (!_active || _endOfPipe.isCompleted) return;
      if (chunk.length > _bytes.length - _length) {
        _failPipe();
        return;
      }
      _bytes.setRange(_length, _length + chunk.length, chunk);
      _length += chunk.length;
    } finally {
      // dart:io pipe chunks are mutable owned byte buffers.
      chunk.fillRange(0, chunk.length, 0);
    }
  }

  void _failResponse([
    PlatformProtectorFailureCode code =
        PlatformProtectorFailureCode.operationFailed,
  ]) {
    if (!_response.isCompleted) {
      final failure = PlatformProtectorFailure(code);
      _terminalFailure ??= failure;
      _response.completeError(failure);
    }
  }

  void _failPipe() {
    if (!_endOfPipe.isCompleted) {
      const failure = PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
      _terminalFailure ??= failure;
      _endOfPipe.completeError(failure);
    }
  }

  void _checkActive() {
    if (_terminalFailure case final failure?) {
      throw failure;
    }
    if (!_active) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
  }

  Future<void> _cleanup({required bool abort}) {
    _reader?.cancel();
    _pipe?.closeReader();
    return _cleanupFuture ??= Future.wait<void>([
      if (_pipe != null) _pipe!.closeWriter(),
      _closeConnection(abort: abort),
    ]).then((_) {});
  }

  Future<void> _closeConnection({required bool abort}) async {
    if (abort && _requestStarted && !_responseReceived) {
      try {
        // Let no-reply Close reach the socket before tearing it down. This
        // cleanup grace does not extend the caller's absolute deadline, and a
        // wedged dispatch cannot prevent a later connection-close attempt.
        await client
            .closeRequest(owner: _owner!, path: _path!)
            .timeout(const Duration(milliseconds: 100));
      } catch (_) {
        // Closing the caller connection is the remaining cancellation path.
      }
    }
    await client.close();
  }
}

bool _isUniqueName(String? name) =>
    name != null && RegExp(r'^:[0-9]+(?:\.[0-9]+)+$').hasMatch(name);

PlatformProtectorFailure _redact(Object error) {
  if (error is PlatformProtectorFailure) return error;
  if (error is SocketException) {
    return const PlatformProtectorFailure(
      PlatformProtectorFailureCode.unavailable,
    );
  }
  if (error is DBusMethodResponseException &&
      const <String>{
        'org.freedesktop.DBus.Error.ServiceUnknown',
        'org.freedesktop.DBus.Error.NameHasNoOwner',
        'org.freedesktop.DBus.Error.UnknownInterface',
        'org.freedesktop.DBus.Error.UnknownMethod',
        'org.freedesktop.DBus.Error.UnknownObject',
        'org.freedesktop.DBus.Error.NotSupported',
        'org.freedesktop.DBus.Error.Spawn.ExecFailed',
        'org.freedesktop.DBus.Error.Spawn.ChildExited',
        'org.freedesktop.DBus.Error.Spawn.ChildSignaled',
        'org.freedesktop.DBus.Error.Spawn.ServiceNotFound',
        'org.freedesktop.DBus.Error.Spawn.Failed',
      }.contains(error.errorName)) {
    return const PlatformProtectorFailure(
      PlatformProtectorFailureCode.unavailable,
    );
  }
  return const PlatformProtectorFailure(
    PlatformProtectorFailureCode.operationFailed,
  );
}

final class _SystemPortalConnection implements LinuxSecretPortalConnection {
  _SystemPortalConnection() : this.withDbusClient(DBusClient.session());

  _SystemPortalConnection.withDbusClient(this._client);

  final DBusClient _client;
  StreamSubscription<DBusSignal>? _subscription;
  var _closed = false;

  @override
  String get uniqueName => _client.uniqueName;

  @override
  Future<String?> resolveOwner({required bool activate}) async {
    _checkOpen();
    var owner = await _client.getNameOwner(_portalName);
    _checkOpen();
    if (owner == null && activate) {
      await _client.startServiceByName(_portalName);
      _checkOpen();
      owner = await _client.getNameOwner(_portalName);
      _checkOpen();
    }
    return owner;
  }

  @override
  Future<void> subscribeResponse({
    required DBusObjectPath path,
    required void Function(DBusSignal) onResponse,
    required void Function() onError,
  }) async {
    _checkOpen();
    // dbus 0.7.15's listen starts AddMatch without exposing its future. Install
    // the local listener first, trap that asynchronous setup error, then await
    // an explicit AddMatch acknowledgement before sending RetrieveSecret.
    // This dedicated connection owns both match references until close.
    runZonedGuarded<void>(() {
      _subscription = DBusSignalStream(
        _client,
        path: path,
        interface: _requestInterface,
        name: 'Response',
      ).listen(onResponse, onError: (Object _) => onError());
    }, (Object _, StackTrace _) => onError());
    await _client.callMethod(
      destination: 'org.freedesktop.DBus',
      path: DBusObjectPath('/org/freedesktop/DBus'),
      interface: 'org.freedesktop.DBus',
      name: 'AddMatch',
      values: [
        DBusString(
          "type='signal',interface='$_requestInterface',member='Response',path='${path.value}'",
        ),
      ],
      replySignature: DBusSignature(''),
    );
    _checkOpen();
  }

  @override
  Future<DBusMethodSuccessResponse> retrieve({
    required String owner,
    required String handleToken,
    required RandomAccessFile output,
  }) {
    _checkOpen();
    return _client.callMethod(
      destination: owner,
      path: _portalPath,
      interface: _secretInterface,
      name: 'RetrieveSecret',
      values: [
        DBusUnixFd(ResourceHandle.fromFile(output)),
        DBusDict.stringVariant({'handle_token': DBusString(handleToken)}),
      ],
      replySignature: DBusSignature('o'),
      noAutoStart: true,
    );
  }

  @override
  Future<void> closeRequest({
    required String owner,
    required DBusObjectPath path,
  }) async {
    if (_closed) return;
    await _client.callMethod(
      destination: owner,
      path: path,
      interface: _requestInterface,
      name: 'Close',
      replySignature: DBusSignature(''),
      noReplyExpected: true,
      noAutoStart: true,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait<void>([
      if (_subscription != null) _subscription!.cancel(),
      _client.close(),
    ]);
  }

  void _checkOpen() {
    if (_closed) {
      _client.close().ignore();
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.operationFailed,
      );
    }
  }
}
