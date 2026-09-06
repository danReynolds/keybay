/// Internal provider-boundary errors translated into the public V2 taxonomy.
library;

/// Base type for failures emitted by low-level platform bindings.
///
/// These errors never cross the public Keybay V2 boundary. Platform profiles
/// map them to redacted [KeybayException] values.
sealed class SecretStoreException implements Exception {
  const SecretStoreException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// The selected OS protector is locked or requires disallowed interaction.
final class KeystoreLocked extends SecretStoreException {
  const KeystoreLocked([String? detail])
    : super(
        'keystore_locked',
        detail ?? 'The OS keystore is locked or requires interaction.',
      );
}

/// The selected OS protector cannot be reached.
final class KeystoreUnreachable extends SecretStoreException {
  const KeystoreUnreachable([String? detail])
    : super(
        'keystore_unreachable',
        detail ?? 'No usable OS keystore provider is available.',
      );
}

/// A low-level provider operation failed without a more specific class.
final class KeystoreOperationFailed extends SecretStoreException {
  const KeystoreOperationFailed(String detail, {this.status})
    : super('keystore_operation_failed', detail);

  final int? status;
}
