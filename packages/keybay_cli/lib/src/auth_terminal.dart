import 'dart:typed_data';
import 'package:keybay/keybay.dart';

/// Internal command UI. Credential objects remain static authentication data.
abstract interface class AuthTerminal {
  Future<AuthMethod> chooseMethod(List<AuthMethod> methods, {String? summary});
  Future<HardwarePrompt> hardware(PasskeyMethod method, {String? summary});
}

/// Owns the attended terminal until the hardware operation has fully drained.
abstract interface class HardwarePrompt {
  PasskeyCancellation get cancellation;
  Future<Uint8List> readPin();
  void check();
  Future<void> close();
}
