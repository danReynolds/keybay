/// Passphrase-key derivation for the Keybay V2 store format.
part of 'keybay_v2.dart';

/// Argon2 version encoded by Keybay V2 passphrase profile 1.
const int v2PassphraseProfile1ArgonVersion = 19;

/// Memory cost in KiB for Keybay V2 passphrase profile 1.
const int v2PassphraseProfile1MemoryKiB = 64 * 1024;

/// Iteration count for Keybay V2 passphrase profile 1.
const int v2PassphraseProfile1Iterations = 3;

/// Lane count for Keybay V2 passphrase profile 1.
const int v2PassphraseProfile1Parallelism = 4;

/// Stable failures from the passphrase-derivation boundary.
enum V2PassphraseDerivationFailureCode { invalidInput, operationFailed }

/// A redacted failure from passphrase-key derivation.
final class V2PassphraseDerivationFailure implements Exception {
  const V2PassphraseDerivationFailure(this.code);

  final V2PassphraseDerivationFailureCode code;

  @override
  String toString() => 'V2PassphraseDerivationFailure(${code.name})';
}

/// Injectable passphrase-key derivation boundary for the common V2 engine.
///
/// Implementations synchronously snapshot [passphrase] and [salt], retain no
/// aliases after the returned future settles, and return a fresh caller-owned
/// 32-byte key. Callers own and must clear the returned buffer.
abstract interface class V2PassphraseDeriver {
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  });
}

/// Hands an operation-owned credential to a deriver, then releases it as soon
/// as the deriver has synchronously taken the snapshot required by its
/// contract. Awaiting the returned future never extends the credential's
/// lifetime.
Future<Uint8List> _derivePassphraseAndReleaseCredential({
  required V2PassphraseDeriver deriver,
  required _CredentialSnapshot credential,
  required int profileId,
  required Uint8List salt,
}) {
  try {
    return deriver.derive(
      passphrase: credential.bytes,
      profileId: profileId,
      salt: salt,
    );
  } finally {
    credential.clear();
  }
}

/// The production Argon2id-v19 implementation of V2 passphrase profile 1.
///
/// Derivations are serialized within the current Dart isolate so concurrent
/// callers cannot multiply the profile's 64 MiB working-memory cost there.
final class Argon2idV2PassphraseDeriver implements V2PassphraseDeriver {
  const Argon2idV2PassphraseDeriver();

  static const DartArgon2id _profile1 = DartArgon2id(
    parallelism: v2PassphraseProfile1Parallelism,
    memory: v2PassphraseProfile1MemoryKiB,
    iterations: v2PassphraseProfile1Iterations,
    hashLength: V2StoreLimits.storeKeyBytes,
  );

  @override
  Future<Uint8List> derive({
    required Uint8List passphrase,
    required int profileId,
    required Uint8List salt,
  }) {
    if (profileId != v2FirstPassphraseProfile) {
      return Future<Uint8List>.error(
        const V2FormatFailure(V2FormatFailureCode.unsupportedKdfProfile),
      );
    }
    if (passphrase.isEmpty ||
        passphrase.length > 1024 ||
        salt.length != V2StoreLimits.argonSaltBytes) {
      return Future<Uint8List>.error(
        const V2PassphraseDerivationFailure(
          V2PassphraseDerivationFailureCode.invalidInput,
        ),
      );
    }

    Uint8List? passphraseSnapshot;
    Uint8List? saltSnapshot;
    try {
      passphraseSnapshot = Uint8List.fromList(passphrase);
      saltSnapshot = Uint8List.fromList(salt);
      return _serializeV2PassphraseDerivation(
        passphrase: passphraseSnapshot,
        salt: saltSnapshot,
      );
    } on Object catch (error, stackTrace) {
      if (passphraseSnapshot != null) _clearBytes(passphraseSnapshot);
      return Future<Uint8List>.error(error, stackTrace);
    }
  }
}

/// Small isolate-local serial queue used to bound concurrent KDF memory.
///
/// It is public only to the internal `src` library so queue ordering and
/// failure release can be tested without timing real Argon2 work. Keybay's
/// package export does not expose it.
final class V2PassphraseDerivationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(FutureOr<T> Function() operation) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return _run(previous, release, operation);
  }

  Future<T> _run<T>(
    Future<void> previous,
    Completer<void> release,
    FutureOr<T> Function() operation,
  ) async {
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }
}

final V2PassphraseDerivationQueue _v2PassphraseDerivations =
    V2PassphraseDerivationQueue();

Future<Uint8List> _serializeV2PassphraseDerivation({
  required Uint8List passphrase,
  required Uint8List salt,
}) {
  return _v2PassphraseDerivations.run(
    () => _runV2PassphraseDerivation(passphrase: passphrase, salt: salt),
  );
}

Future<Uint8List> _runV2PassphraseDerivation({
  required Uint8List passphrase,
  required Uint8List salt,
}) async {
  List<int>? derived;
  DartArgon2State? state;
  Object? primaryFailure;
  StackTrace? primaryStack;
  Uint8List? result;
  try {
    state = Argon2idV2PassphraseDeriver._profile1.newState();
    derived = await state.deriveKeyBytes(password: passphrase, nonce: salt);
    if (derived.length != V2StoreLimits.storeKeyBytes) {
      throw const V2PassphraseDerivationFailure(
        V2PassphraseDerivationFailureCode.operationFailed,
      );
    }
    result = Uint8List.fromList(derived);
  } on V2PassphraseDerivationFailure catch (error, stackTrace) {
    primaryFailure = error;
    primaryStack = stackTrace;
  } on Object catch (error, stackTrace) {
    primaryFailure = const V2PassphraseDerivationFailure(
      V2PassphraseDerivationFailureCode.operationFailed,
    );
    primaryStack = stackTrace;
  }

  Object? cleanupFailure;
  StackTrace? cleanupStack;
  try {
    if (derived != null) _clearList(derived);
    state?.tryReleaseMemory();
  } on Object catch (error, stackTrace) {
    cleanupFailure = const V2PassphraseDerivationFailure(
      V2PassphraseDerivationFailureCode.operationFailed,
    );
    cleanupStack = stackTrace;
  } finally {
    _clearBytes(passphrase);
  }

  final failure = primaryFailure ?? cleanupFailure;
  if (failure != null) {
    if (result != null) _clearBytes(result);
    Error.throwWithStackTrace(
      failure,
      primaryStack ?? cleanupStack ?? StackTrace.current,
    );
  }
  return result!;
}

void _clearList(List<int> bytes) {
  for (var index = 0; index < bytes.length; index++) {
    bytes[index] = 0;
  }
}

void _clearBytes(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
