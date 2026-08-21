import 'dart:convert';
import 'dart:io';

import 'critical/watcher.dart';
import 'finding.dart';
import 'peers/watcher.dart';
import 'platforms/watcher.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await run(arguments);
}

Future<int> run(List<String> arguments) async {
  final flags =
      arguments.where((argument) => argument.startsWith('-')).toList();
  final selections =
      arguments.where((argument) => !argument.startsWith('-')).toList();
  const allowedFlags = <String>{'--backfill', '--json'};
  if (flags.any((flag) => !allowedFlags.contains(flag)) ||
      flags.toSet().length != flags.length ||
      selections.length != 1) {
    stderr.writeln(
      'usage: dart run watchers/watch.dart '
      '<platforms|peers|critical> [--json] [--backfill]',
    );
    return 64;
  }
  final selection = selections.single;
  if (!const <String>{'platforms', 'peers', 'critical'}.contains(selection)) {
    stderr.writeln('unknown watcher: $selection');
    return 64;
  }
  final backfill = flags.contains('--backfill');
  if (backfill && selection != 'platforms') {
    stderr.writeln('--backfill is supported only by the platforms watcher');
    return 64;
  }
  final emitJson = flags.contains('--json');
  try {
    final found = switch (selection) {
      'platforms' => backfill
          ? await platformBackfillFindings(
              await _readObject('platforms/config.json'),
            )
          : await platformFindings(
              await _readObject('platforms/config.json'),
            ),
      'peers' => await peerFindings(
          peerBaseline(await _readObject('peers/baseline.json')),
        ),
      'critical' => await criticalFindings(
          await _readObject('critical/config.json'),
        ),
      _ => throw StateError('unreachable watcher selection'),
    };
    if (emitJson) {
      stdout.writeln(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(
            <Map<String, Object>>[for (final item in found) item.toJson()]),
      );
      return 0;
    }
    return _printHuman(selection, found);
  } catch (error) {
    stderr.writeln(
      '${_prefix(selection)}: source or configuration invalid: $error',
    );
    return 69;
  }
}

Future<Map<String, Object?>> _readObject(String relativePath) async {
  final value = jsonDecode(
    await File.fromUri(Platform.script.resolve(relativePath)).readAsString(),
  );
  if (value is! Map) {
    throw FormatException('$relativePath was not an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$relativePath had a non-string key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

int _printHuman(String selection, List<WatcherFinding> found) {
  if (found.isEmpty) {
    switch (selection) {
      case 'platforms':
        stdout.writeln(
          'platform-advisories: no new Apple, Android, or Linux advisories',
        );
      case 'peers':
        stdout.writeln(
          'peer-advisories: no new advisories across ${peers.length} watched packages',
        );
      case 'critical':
        stdout.writeln(
          'critical-dependencies: every reviewed pin is still current',
        );
    }
    return 0;
  }
  switch (selection) {
    case 'platforms':
      for (final finding in found) {
        stdout.writeln('platform-advisories: NEW: ${finding.title}');
      }
    case 'peers':
      stdout.writeln(
        'peer-advisories: NEW advisory IDs — triage against the invariants, '
        'record the decision in the generated GitHub issue:',
      );
      for (final finding in found) {
        final reference = finding.references.single;
        stdout.writeln(
          '  ${reference.label}: ${finding.subjects.join(', ')} '
          '(${reference.url})',
        );
      }
    case 'critical':
      for (final finding in found) {
        stdout.writeln(
          'critical-dependencies: REVIEW REQUIRED: ${finding.title}',
        );
      }
  }
  return 1;
}

String _prefix(String selection) => switch (selection) {
      'platforms' => 'platform-advisories',
      'peers' => 'peer-advisories',
      'critical' => 'critical-dependencies',
      _ => selection,
    };
