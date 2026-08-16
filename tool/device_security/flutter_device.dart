import 'dart:convert';
import 'dart:io';

/// Selects one exact connected physical iOS target from
/// `flutter devices --machine` input and prints only its SDK description.
/// Device names and IDs are deliberately never echoed.
Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      args.single.isEmpty ||
      args.single.length > 128 ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(args.single)) {
    stderr.writeln('flutter-device: one valid device ID is required');
    exitCode = 64;
    return;
  }
  try {
    final decoded = jsonDecode(await utf8.decoder.bind(stdin).join());
    if (decoded is! List) throw const FormatException('expected a JSON list');
    final matches = decoded.whereType<Map<String, Object?>>().where(
          (device) => device['id'] == args.single,
        );
    if (matches.length != 1) {
      throw const FormatException(
          'selected device is not exactly one connected Flutter target');
    }
    final device = matches.single;
    final target = device['targetPlatform'];
    final emulator = device['emulator'];
    final supported = device['isSupported'];
    if (target is! String ||
        target.toLowerCase() != 'ios' ||
        emulator != false ||
        supported != true) {
      throw const FormatException(
          'selected target is not supported physical iOS hardware');
    }
    final sdk = device['sdk'];
    if (sdk is! String ||
        sdk.trim().isEmpty ||
        sdk.length > 256 ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(sdk)) {
      throw const FormatException('selected target has no safe SDK inventory');
    }
    stdout.writeln(sdk.trim());
  } on Object catch (error) {
    stderr.writeln('flutter-device: $error');
    exitCode = 65;
  }
}
