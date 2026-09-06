/// Shared Security.framework failure mapping for V2 Apple protectors.
library;

import '../errors.dart';
import 'entropy_source.dart';
import 'platform_protector.dart';

const int _errSecInteractionRequired = -25315;

/// Maps the common Apple Keychain failures to the internal protector taxonomy.
Future<T> atAppleKeychainProtectorBoundary<T>(
  Future<T> Function() operation,
) async {
  try {
    return await operation();
  } on PlatformProtectorFailure {
    rethrow;
  } on V2EntropyFailure {
    rethrow;
  } on KeystoreLocked {
    throw const PlatformProtectorFailure(PlatformProtectorFailureCode.locked);
  } on KeystoreUnreachable {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.unavailable,
    );
  } on KeystoreOperationFailed catch (failure) {
    throw PlatformProtectorFailure(
      failure.status == _errSecInteractionRequired
          ? PlatformProtectorFailureCode.interactionRequired
          : PlatformProtectorFailureCode.operationFailed,
    );
  } on SecretStoreException {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  } on Object {
    throw const PlatformProtectorFailure(
      PlatformProtectorFailureCode.operationFailed,
    );
  }
}
