import 'dart:convert';
import 'dart:io';

import 'catalog.dart';

final class ResultException implements Exception {
  ResultException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> main(List<String> args) async {
  try {
    final options = _options(args);
    final input = File(_required(options, '--input')).absolute;
    final output = File(_required(options, '--output')).absolute;
    final selection = _required(options, '--selection');
    final nonce = _required(options, '--nonce');
    final subject = _required(options, '--subject');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(nonce)) {
      throw ResultException('nonce must be 64 lowercase hexadecimal digits');
    }
    if (!RegExp(r'^git-commit:[0-9a-f]{40}$').hasMatch(subject)) {
      throw ResultException('invalid source identity');
    }
    final expected = scenariosForSelection(selection)
        .where((scenario) => !scenario.id.endsWith('-001'))
        .map((scenario) => scenario.id)
        .toSet();
    final parsed = await _parseReporter(input, expected, nonce, subject);
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ResultException('output already exists');
    }
    await output.create(exclusive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
            'schema': 'keybay.device-security-results',
            'schema_version': 2,
            'nonce': nonce,
            'subject': subject,
            'selection': selection,
            'command_status': parsed.commandSucceeded ? 'pass' : 'fail',
            'scenarios': [
              for (final id in expected.toList()..sort())
                {
                  'id': id,
                  'status': parsed.scenarios[id] ?? 'blocked',
                  'reason': parsed.scenarios.containsKey(id)
                      ? 'derived from Flutter JSON test reporter'
                      : 'required scenario result was absent',
                },
            ],
          })}\n',
      flush: true,
    );
    stdout.writeln(output.path);
  } on Exception catch (error) {
    stderr.writeln('device-security-result: $error');
    exitCode = error is ResultException ? 64 : 74;
  }
}

Map<String, String> _options(List<String> args) {
  if (args.length.isOdd) {
    throw ResultException('every option requires a value');
  }
  final result = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    final key = args[index];
    if (!const {
      '--input',
      '--output',
      '--selection',
      '--nonce',
      '--subject',
    }.contains(key)) {
      throw ResultException('unknown option: $key');
    }
    if (result.containsKey(key)) {
      throw ResultException('$key may be supplied only once');
    }
    result[key] = args[index + 1];
  }
  return result;
}

String _required(Map<String, String> options, String key) =>
    options[key] ?? (throw ResultException('missing required $key'));

Future<({Map<String, String> scenarios, bool commandSucceeded})> _parseReporter(
  File input,
  Set<String> expected,
  String nonce,
  String subject,
) async {
  if (await FileSystemEntity.type(input.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw ResultException('input must be a regular Flutter JSON report');
  }
  final tests = <Object, String>{};
  final outcomes = <String, List<String>>{};
  var metadataPasses = 0;
  bool? commandSucceeded;
  await for (final line in input
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      throw ResultException('Flutter JSON report contains malformed JSON');
    }
    if (decoded is! Map<String, dynamic>) continue;
    if (decoded['type'] == 'done') {
      if (commandSucceeded != null || decoded['success'] is! bool) {
        throw ResultException(
            'report contained a malformed duplicate done event');
      }
      commandSucceeded = decoded['success'] as bool;
      continue;
    }
    if (decoded['type'] == 'testStart') {
      final test = decoded['test'];
      if (test is Map<String, dynamic> &&
          test['id'] != null &&
          test['name'] is String) {
        tests[test['id'] as Object] = test['name'] as String;
      }
      continue;
    }
    if (decoded['type'] != 'testDone') continue;
    final id = decoded['testID'];
    final name = tests[id];
    if (name == null) continue;
    final skipped = decoded['skipped'] == true;
    final result = decoded['result'];
    final status = skipped
        ? 'skipped'
        : result == 'success'
            ? 'pass'
            : result == 'failure' || result == 'error'
                ? 'fail'
                : 'inconclusive';
    if (name
        .contains('KEYBAY-SECURITY-METADATA nonce=$nonce subject=$subject')) {
      if (status == 'pass') metadataPasses++;
    }
    for (final scenario in expected) {
      if (RegExp('(^| )${RegExp.escape(scenario)}( |\$)').hasMatch(name)) {
        outcomes.putIfAbsent(scenario, () => <String>[]).add(status);
      }
    }
  }
  if (metadataPasses != 1) {
    throw ResultException(
        'report must contain one passing nonce/subject metadata test');
  }
  final derived = <String, String>{};
  for (final scenario in expected) {
    final values = outcomes[scenario];
    if (values == null) continue;
    if (values.length != 1) {
      throw ResultException('scenario $scenario appeared more than once');
    }
    derived[scenario] = values.single;
  }
  return (
    scenarios: derived,
    // A killed or truncated command has no done event. It is never a pass.
    commandSucceeded: commandSucceeded ?? false,
  );
}
