import 'dart:convert';
import 'dart:io';

/// Selects one exact connected physical iOS target from
/// joined Flutter/Xcode inventory and prints its model and SDK description.
/// Xcode supplies the hardware model; Flutter's name can be a personal label.
/// The raw device ID is deliberately never echoed.
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
    if (decoded is! Map<String, dynamic> ||
        decoded['flutter'] is! List ||
        decoded['apple'] is! List) {
      throw const FormatException('expected joined Flutter/Xcode inventory');
    }
    final flutter = (decoded['flutter'] as List)
        .whereType<Map<String, Object?>>();
    final apple = (decoded['apple'] as List).whereType<Map<String, Object?>>();
    if (args.single == '--list') {
      for (final device in flutter.where(
        (device) =>
            device['targetPlatform'] == 'ios' &&
            device['emulator'] == false &&
            device['isSupported'] == true,
      )) {
        final facts = _physicalFacts(device, apple);
        stdout.writeln('${facts.model}\t${facts.sdk}');
      }
      return;
    }
    final matches = flutter.where((device) => device['id'] == args.single);
    if (matches.length != 1) {
      throw const FormatException(
        'selected device is not exactly one connected Flutter target',
      );
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
        'selected target is not supported physical iOS hardware',
      );
    }
    final facts = _physicalFacts(device, apple);
    stdout.writeln('${facts.model}\t${facts.sdk}');
  } on Object {
    stderr.writeln(
      'flutter-device: invalid or mismatched physical device inventory',
    );
    exitCode = 65;
  }
}

({String model, String sdk}) _physicalFacts(
  Map<String, Object?> device,
  Iterable<Map<String, Object?>> apple,
) {
  final matches = apple.where(
    (entry) =>
        entry['identifier'] == device['id'] &&
        entry['simulator'] == false &&
        entry['available'] == true &&
        entry['platform'] == 'com.apple.platform.iphoneos',
  );
  if (matches.length != 1) {
    throw const FormatException(
      'selected target has no exact physical Xcode identity',
    );
  }
  final model = matches.single['modelName'];
  final sdk = device['sdk'];
  for (final value in [model, sdk]) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > 256 ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value)) {
      throw const FormatException(
        'selected target has no safe model/SDK inventory',
      );
    }
  }
  return (model: (model as String).trim(), sdk: (sdk as String).trim());
}
