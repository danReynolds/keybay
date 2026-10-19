import 'dart:typed_data';
import 'package:keybay/keybay.dart';

/// Shown before a passphrase or PIN prompt in an X11 session, where any client
/// can read keystrokes typed into another.
const String x11Warning =
    'Warning: under X11, other programs can read what you type.';

/// Internal command UI. Credential objects remain static authentication data.
abstract interface class AuthTerminal {
  Future<AuthMethod> chooseMethod(List<AuthMethod> methods, {String? summary});
  Future<HardwarePrompt> hardware(PasskeyMethod method, {String? summary});
}

/// Owns the attended terminal until the hardware operation has fully drained.
abstract interface class HardwarePrompt {
  PasskeyCancellation get cancellation;

  /// Reads the key's PIN, first showing [warning] when it is given.
  Future<Uint8List> readPin({String? warning});
  void check();
  Future<void> close();
}
