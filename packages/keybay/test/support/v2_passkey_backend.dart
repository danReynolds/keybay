import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keypass/keypass_backend.dart' as kp;

/// Disposable credential provider behind the real Keypass facade. It models
/// successful native verification, not physical authenticators or their crypto.
/// Keybay still exercises its real result ownership, KDF, envelope and engine.
final class TestPasskeyProvider {
  final List<kp.PasskeyRegistrationRequest> registrations = [];
  final List<kp.PasskeyBinding> evaluations = [];
  final List<Uint8List> transferredSecrets = [];
  final List<_TestPasskeyBackend> _backends = [];
  final Map<String, _Credential> _credentials = {};
  bool wrongNextSecret = false;
  bool counterless = false;
  kp.PasskeyErrorCode? nextFailure;
  FutureOr<void> Function()? afterNextSecret;

  int get operationCount => _backends.length;

  kp.Keypass client(PasskeyCredential credential) =>
      kp.keypassWithBackendFactory(
        rpId: credential.rpId,
        displayName: credential.displayName,
        route: credential.route,
        createBackend: () {
          final backend = _TestPasskeyBackend(this, credential.route);
          _backends.add(backend);
          return backend;
        },
      );

  /// Deliberate test aliases observe production KeypassResult.dispose() and
  /// cancellation cleanup. The fake never clears these on the facade's behalf.
  void expectReleased() {
    if (_backends.any((backend) => backend.disposeCount != 1)) {
      throw StateError('Every Keypass backend must be disposed exactly once.');
    }
    for (final bytes in transferredSecrets) {
      if (bytes.any((byte) => byte != 0)) {
        throw StateError('Returned PRF material must be cleared.');
      }
    }
  }

  Future<kp.PasskeyBinding> _register(
    kp.PasskeyRegistrationRequest request,
    PasskeyRoute route,
  ) async {
    registrations.add(request);
    final sequence = registrations.length;
    final id = Uint8List.fromList([sequence, ...List<int>.filled(31, 0x42)]);
    _credentials[base64UrlEncode(id)] = _Credential(
      Uint8List.fromList([
        for (var index = 0; index < 32; index++)
          (sequence * 17 + index * 7) & 0xff,
      ]),
    );
    return kp.PasskeyBinding(
      domain: request.domain,
      route: route,
      transports: route == PasskeyRoute.hardware ? ['usb'] : [],
      credentialId: id,
      userId: request.userId,
      // This is trusted-adapter test metadata, not a verified COSE key.
      publicKeyCose: Uint8List.fromList([0xa0]),
      input: request.input,
      authenticatorState: _state(route, 0),
    );
  }

  Future<kp.PasskeyAssertion> _evaluate(
    kp.PasskeyEvaluationRequest request,
  ) async {
    final binding = request.bindings.single;
    evaluations.add(binding);
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw kp.PasskeyException(failure);
    final credential = _credentials[base64UrlEncode(binding.credentialId)];
    if (credential == null) {
      throw const kp.PasskeyException(
        kp.PasskeyErrorCode.credentialUnavailable,
      );
    }
    final secret = Uint8List.fromList(credential.secret);
    if (wrongNextSecret) {
      wrongNextSecret = false;
      secret[0] ^= 1;
    }
    transferredSecrets.add(secret);
    final hook = afterNextSecret;
    afterNextSecret = null;
    await hook?.call();
    return kp.PasskeyAssertion(
      credentialId: binding.credentialId,
      secret: secret,
      state: _state(binding.route, counterless ? 0 : ++credential.signCount),
    );
  }

  void clear() {
    for (final credential in _credentials.values) {
      credential.secret.fillRange(0, credential.secret.length, 0);
    }
    _credentials.clear();
  }
}

final class _Credential {
  _Credential(this.secret);
  final Uint8List secret;
  int signCount = 0;
}

kp.AuthenticatorState _state(PasskeyRoute route, int signCount) =>
    kp.AuthenticatorState(
      backupEligible: route == PasskeyRoute.system,
      backupState: route == PasskeyRoute.system,
      signCount: signCount,
    );

final class _TestPasskeyBackend implements kp.PasskeyBackend {
  _TestPasskeyBackend(this.provider, this.route);
  final TestPasskeyProvider provider;
  final PasskeyRoute route;
  int disposeCount = 0;

  @override
  Future<kp.PasskeyAvailability> availability() async =>
      const kp.PasskeyAvailability.ready();

  @override
  Future<kp.PasskeyBinding> register(
    kp.PasskeyRegistrationRequest request,
    kp.PasskeyCancellation cancellation,
  ) => provider._register(request, route);

  @override
  Future<kp.PasskeyAssertion> evaluate(
    kp.PasskeyEvaluationRequest request,
    kp.PasskeyCancellation cancellation,
  ) => provider._evaluate(request);

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}
