import 'dart:async';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/format/store_format.dart';
import 'package:keybay/src/v2/host_platform.dart';
import 'package:keybay/src/v2/keybay_v2.dart'
    show V2PassphraseDeriver, V2StoreEngine;

import 'v2_pinned_store_files.dart';
import 'v2_platform_fakes.dart';

/// A test assembly of the production V2 engine and disposable boundary fakes.
///
/// This class contains no storage, session, authentication, or rotation logic.
/// Those behaviors are exercised through [V2StoreEngine].
final class V2TestKeybay {
  V2TestKeybay({String applicationId = 'dev.keybay.public-api-test'}) {
    binding = ResolvedApplicationBinding.derive(
      identity: ApplicationIdentity(
        stableValue: applicationId,
        source: ApplicationIdentitySource.test,
        assurance: ApplicationIdentityAssurance.namespaceOnly,
      ),
      profile: HostProfile('public-api-test'),
      canonicalFileRoot: Uri.parse('file:///keybay-test/$applicationId/'),
    );
    files = MemoryPinnedStoreFiles(binding);
    registry = InMemoryRootRegistry();
    protector = SoftwareTestProtector(binding: binding, registry: registry);
    platform = FakeHostPlatform(
      ResolvedHost(binding: binding, files: files, protector: protector),
    );
    deriver = FastTestPassphraseDeriver();
    engine = V2StoreEngine(platform, passphraseDeriver: deriver);
  }

  late final ResolvedApplicationBinding binding;
  late final MemoryPinnedStoreFiles files;
  late final InMemoryRootRegistry registry;
  late final SoftwareTestProtector protector;
  late final FakeHostPlatform platform;
  late final FastTestPassphraseDeriver deriver;
  late final V2StoreEngine engine;
  bool _disposed = false;

  Future<KeybaySession> open({KeybayCredential? credential}) =>
      engine.open(credential: credential);

  Future<void> reset() => engine.reset();

  /// Pauses the next production-engine file open at a deterministic boundary.
  void gateNextOperation(Future<void> gate) {
    if (files.beforeOpen != null) {
      throw StateError('A test operation gate is already installed.');
    }
    files.beforeOpen = () async {
      files.beforeOpen = null;
      await gate;
    };
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (files.beforeOpen != null) {
      files.beforeOpen = null;
    }
    try {
      await engine.reset();
    } on Object {
      // A failed assertion may deliberately leave disposable partial state.
    }
  }
}

/// Fast deterministic derivation for lifecycle tests, never production crypto.
///
/// Retaining the borrowed test alias lets tests verify that the production
/// engine clears its operation-owned credential snapshot.
final class FastTestPassphraseDeriver implements V2PassphraseDeriver {
  final List<Uint8List> _borrowedInputs = <Uint8List>[];

  bool get lastBorrowedInputIsCleared =>
      _borrowedInputs.isNotEmpty &&
      _borrowedInputs.last.every((byte) => byte == 0);

  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) async {
    _borrowedInputs.add(passphrase);
    var state = 0x811c9dc5 ^ profileId;
    for (final byte in passphrase) {
      state = ((state ^ byte) * 0x01000193) & 0xffffffff;
    }
    for (final byte in salt) {
      state = ((state ^ byte) * 0x01000193) & 0xffffffff;
    }
    return Uint8List.fromList(<int>[
      for (var index = 0; index < V2StoreLimits.storeKeyBytes; index++)
        ((state = _mix(state + index)) >> ((index & 3) * 8)) & 0xff,
    ]);
  }
}

int _mix(int value) {
  var mixed = value & 0xffffffff;
  mixed ^= mixed << 13;
  mixed ^= mixed >> 17;
  mixed ^= mixed << 5;
  return mixed & 0xffffffff;
}
