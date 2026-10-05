import 'package:keypass/keypass.dart';

import '../failure.dart';
import 'native_model.dart' show cliHardwareRpId;
import 'store.dart';

/// Discovery only: never submits a PIN, creates a passkey or asks for a touch.
Future<bool> hardwareConnected(TuiCancellation cancellation) async {
  final signal = PasskeyCancellation();
  cancellation.bind(signal.cancel);
  try {
    final state = await Keypass.hardware(
      rpId: cliHardwareRpId,
    ).check(cancellation: signal);
    if (cancellation.isCancelled) return false;
    if (state.canAttempt) return true;
    if (state.reason == PasskeyErrorCode.deviceUnavailable) return false;
    throw TuiStoreException(
      hardwareFailureMessage(state.reason),
      hardware: true,
    );
  } on PasskeyException catch (error) {
    if (cancellation.isCancelled) return false;
    throw TuiStoreException(hardwareFailureMessage(error.code), hardware: true);
  } finally {
    cancellation.unbind();
  }
}
