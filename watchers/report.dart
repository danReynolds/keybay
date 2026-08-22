import 'dart:convert';
import 'dart:io';

const watcherNames = <String>['dependencies', 'platforms', 'peers'];
const _statuses = <String>{'quiet', 'findings', 'failed', 'not_run'};
final _marker = RegExp(r'^[A-Za-z0-9._/-]{1,240}$');
final _commit = RegExp(r'^[0-9a-f]{40,64}$');
final _runId = RegExp(r'^[1-9][0-9]{0,19}$');
final _reportDirectory =
    RegExp(r'^\d{4}-\d{2}-\d{2}-[1-9][0-9]{0,19}-[1-9][0-9]{0,19}$');

final class ReportInput {
  const ReportInput({
    required this.watcher,
    required this.status,
    required this.findings,
    this.error,
  });

  final String watcher;
  final String status;
  final List<ReportFinding> findings;
  final String? error;

  factory ReportInput.fromJson(Object? raw, String expectedWatcher) {
    final object = _object(raw, '$expectedWatcher report input');
    final watcher = object['watcher'];
    final status = object['status'];
    final error = object['error'];
    final rawFindings = object['findings'];
    if (watcher != expectedWatcher || !watcherNames.contains(watcher)) {
      throw FormatException('unexpected watcher in $expectedWatcher input');
    }
    if (status is! String || !_statuses.contains(status)) {
      throw FormatException('$expectedWatcher had an invalid status');
    }
    if (rawFindings is! List || rawFindings.length > 1000) {
      throw FormatException(
          '$expectedWatcher findings were invalid or too many');
    }
    final findings = <ReportFinding>[
      for (final finding in rawFindings)
        ReportFinding.fromJson(finding, expectedWatcher),
    ];
    if (status == 'quiet' && findings.isNotEmpty) {
      throw FormatException('$expectedWatcher was quiet with findings');
    }
    if (status == 'findings' && findings.isEmpty) {
      throw FormatException('$expectedWatcher reported findings without any');
    }
    if ((status == 'failed' || status == 'not_run') &&
        (error is! String || error.trim().isEmpty)) {
      throw FormatException('$expectedWatcher $status without a reason');
    }
    if (error != null && error is! String) {
      throw FormatException('$expectedWatcher error was not text');
    }
    return ReportInput(
      watcher: expectedWatcher,
      status: status,
      findings: findings,
      error:
          error == null ? null : _plain(error as String, 1000, 'watcher error'),
    );
  }
}

final class ReportFinding {
  const ReportFinding({
    required this.marker,
    required this.title,
    required this.subjects,
    required this.references,
  });

  final String marker;
  final String title;
  final List<String> subjects;
  final List<({String label, String url})> references;

  factory ReportFinding.fromJson(Object? raw, String expectedWatcher) {
    final object = _object(raw, 'watcher finding');
    if (object['watcher'] != expectedWatcher) {
      throw FormatException('finding did not belong to $expectedWatcher');
    }
    final marker = object['marker'];
    final title = object['title'];
    final rawSubjects = object['subjects'];
    final rawReferences = object['references'];
    if (marker is! String || !_marker.hasMatch(marker)) {
      throw const FormatException('finding marker was unsafe');
    }
    if (title is! String) {
      throw const FormatException('finding title was not text');
    }
    if (rawSubjects is! List ||
        rawSubjects.isEmpty ||
        rawSubjects.length > 100 ||
        rawSubjects.any((subject) => subject is! String)) {
      throw const FormatException('finding subjects were invalid');
    }
    if (rawReferences is! List ||
        rawReferences.isEmpty ||
        rawReferences.length > 20) {
      throw const FormatException('finding references were invalid');
    }
    final references = <({String label, String url})>[];
    for (final rawReference in rawReferences) {
      final reference = _object(rawReference, 'finding reference');
      final label = reference['label'];
      final url = reference['url'];
      if (label is! String || url is! String) {
        throw const FormatException('finding reference was malformed');
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          url.length > 2048) {
        throw const FormatException('finding reference URL was unsafe');
      }
      references.add(
        (
          label: _plain(label, 200, 'reference label'),
          url: uri.toString(),
        ),
      );
    }
    return ReportFinding(
      marker: marker,
      title: _plain(title, 300, 'finding title'),
      subjects: <String>[
        for (final subject in rawSubjects.cast<String>())
          _plain(subject, 300, 'finding subject'),
      ],
      references: references,
    );
  }
}

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty) throw const FormatException('missing command');
    final options = _options(arguments.skip(1).toList());
    switch (arguments.first) {
      case 'create':
        await createReport(
          runId: _required(options, 'run-id'),
          attempt: _required(options, 'attempt'),
          event: _required(options, 'event'),
          commit: _required(options, 'commit'),
          startedAt: _timestamp(_required(options, 'started-at')),
          inputs: <String, File>{
            for (final watcher in watcherNames)
              watcher: File(_required(options, watcher)),
          },
          outputDirectory: Directory(_required(options, 'output')),
        );
      case 'summary':
        await writeSummary(
          Directory(_required(options, 'reports')),
          File(_required(options, 'output')),
        );
      default:
        throw FormatException('unknown command: ${arguments.first}');
    }
  } on FormatException catch (error) {
    stderr.writeln('watcher-report: $error');
    exitCode = 64;
  }
}

Future<void> createReport({
  required String runId,
  required String attempt,
  required String event,
  required String commit,
  required DateTime startedAt,
  required Map<String, File> inputs,
  required Directory outputDirectory,
}) async {
  if (!_runId.hasMatch(runId) || !_runId.hasMatch(attempt)) {
    throw const FormatException('run ID and attempt must be positive integers');
  }
  if (!const <String>{'schedule', 'workflow_dispatch'}.contains(event)) {
    throw const FormatException('unsupported watcher report event');
  }
  if (!_commit.hasMatch(commit)) {
    throw const FormatException('source commit was invalid');
  }
  if (inputs.keys.toSet().difference(watcherNames.toSet()).isNotEmpty ||
      watcherNames.any((watcher) => !inputs.containsKey(watcher))) {
    throw const FormatException('all watcher inputs are required');
  }
  final parsed = <String, ReportInput>{};
  for (final watcher in watcherNames) {
    final file = inputs[watcher]!;
    Object? raw;
    try {
      raw = jsonDecode(await file.readAsString());
    } on FileSystemException catch (error) {
      throw FormatException('could not read $watcher input: $error');
    } on FormatException catch (error) {
      throw FormatException('$watcher input was not JSON: $error');
    }
    parsed[watcher] = ReportInput.fromJson(raw, watcher);
  }
  if (await outputDirectory.exists()) {
    throw FormatException(
        'report directory already exists: ${outputDirectory.path}');
  }
  await outputDirectory.create(recursive: true);
  final reportId = 'github-$runId-$attempt';
  final metadata = <String, Object>{
    'schema': 1,
    'report_id': reportId,
    'run_id': runId,
    'attempt': attempt,
    'event': event,
    'commit': commit,
    'run_url': 'https://github.com/danReynolds/keybay/actions/runs/$runId',
    'started_at': startedAt.toUtc().toIso8601String(),
    'statuses': <String, String>{
      for (final watcher in watcherNames) watcher: parsed[watcher]!.status,
    },
  };
  await File('${outputDirectory.path}/raw.md').writeAsString(
    _rawMarkdown(metadata, parsed),
  );
  final assessmentMetadata = <String, Object>{
    'schema': 1,
    'report_id': reportId,
    'status': 'pending',
    'summary': 'Awaiting Codex assessment.',
    'actions': <Object>[],
  };
  await File('${outputDirectory.path}/assessment.md').writeAsString(
    '${_comment('keybay-watcher-assessment', assessmentMetadata)}\n\n'
    '# Assessment\n\n'
    'Status: **Pending Codex review**\n\n'
    'The raw watcher output has not yet been assessed for Keybay applicability.\n',
  );
}

Future<void> writeSummary(Directory reports, File output) async {
  final rows = <_SummaryRow>[];
  if (await reports.exists()) {
    await for (final entity in reports.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final rawFile = File('${entity.path}/raw.md');
      final assessmentFile = File('${entity.path}/assessment.md');
      if (!await rawFile.exists() || !await assessmentFile.exists()) {
        throw FormatException('${entity.path} was not a complete report');
      }
      final raw = _metadata(
        await rawFile.readAsString(),
        'keybay-watcher-report',
      );
      final assessment = _metadata(
        await assessmentFile.readAsString(),
        'keybay-watcher-assessment',
      );
      final reportId = raw['report_id'];
      if (raw['schema'] != 1 ||
          assessment['schema'] != 1 ||
          reportId is! String ||
          assessment['report_id'] != reportId) {
        throw FormatException('${entity.path} had mismatched report IDs');
      }
      final startedAt = _timestampValue(raw['started_at'], 'report started_at');
      final statuses = _object(raw['statuses'], 'report statuses');
      final assessmentStatus = assessment['status'];
      final summary = assessment['summary'];
      final actions = assessment['actions'];
      if (!const <String>{'pending', 'assessed', 'needs_attention'}
              .contains(assessmentStatus) ||
          summary is! String ||
          actions is! List) {
        throw FormatException('${entity.path} had invalid assessment metadata');
      }
      final links = <({String label, String url})>[];
      for (final rawAction in actions) {
        final action = _object(rawAction, 'assessment action');
        final label = action['label'];
        final url = action['url'];
        if (label is! String || url is! String || !_keybayActionUrl(url)) {
          throw const FormatException('assessment action was unsafe');
        }
        links.add((label: _plain(label, 100, 'action label'), url: url));
      }
      final directory =
          entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      if (!_reportDirectory.hasMatch(directory)) {
        throw FormatException('${entity.path} had an invalid directory name');
      }
      rows.add(
        _SummaryRow(
          directory: directory,
          startedAt: startedAt,
          statuses: <String, String>{
            for (final watcher in watcherNames)
              watcher: _status(statuses[watcher], watcher),
          },
          assessmentStatus: assessmentStatus as String,
          assessmentSummary: _plain(summary, 300, 'assessment summary'),
          actions: links,
        ),
      );
    }
  }
  rows.sort((left, right) => right.startedAt.compareTo(left.startedAt));
  final buffer = StringBuffer()
    ..writeln('# Security watcher reports')
    ..writeln()
    ..writeln(
      'Generated history of weekly and on-demand watcher runs. Raw findings are inputs, not vulnerability determinations; each run is completed by a Codex assessment.',
    )
    ..writeln()
    ..writeln(
        '| Run | Dependencies | Platforms | Peers | AI assessment | Actions |')
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  if (rows.isEmpty) {
    buffer.writeln('| None yet | — | — | — | — | — |');
  } else {
    for (final row in rows) {
      final date = row.startedAt.toUtc().toIso8601String().split('T').first;
      final assessment = '${_md(row.assessmentStatus)}: '
          '[${_md(row.assessmentSummary)}](${row.directory}/assessment.md)';
      final actions = row.actions.isEmpty
          ? 'None'
          : row.actions
              .map((action) => '[${_md(action.label)}](${action.url})')
              .join(', ');
      buffer.writeln(
        '| [$date](${row.directory}/raw.md) | '
        '${_md(row.statuses['dependencies']!)} | '
        '${_md(row.statuses['platforms']!)} | '
        '${_md(row.statuses['peers']!)} | $assessment | $actions |',
      );
    }
  }
  await output.parent.create(recursive: true);
  await output.writeAsString(buffer.toString());
}

String _rawMarkdown(
  Map<String, Object> metadata,
  Map<String, ReportInput> inputs,
) {
  final buffer = StringBuffer()
    ..writeln(_comment('keybay-watcher-report', metadata))
    ..writeln()
    ..writeln('# Raw security watcher report')
    ..writeln()
    ..writeln(
      'This is immutable discovery output. A finding means “review this,” not “Keybay is vulnerable.”',
    )
    ..writeln()
    ..writeln(
      '- Report: [`${metadata['report_id']}`](${metadata['run_url']}) (attempt `${metadata['attempt']}`)',
    )
    ..writeln('- Started: `${metadata['started_at']}`')
    ..writeln('- Source commit: `${metadata['commit']}`')
    ..writeln('- GitHub event: `${metadata['event']}`');
  for (final watcher in watcherNames) {
    final input = inputs[watcher]!;
    buffer
      ..writeln()
      ..writeln('## ${_heading(watcher)}')
      ..writeln()
      ..writeln('Sources: ${_sourceDescription(watcher)}')
      ..writeln()
      ..writeln('Status: **${_md(input.status)}**');
    if (input.error case final error?) {
      buffer
        ..writeln()
        ..writeln('Failure: ${_md(error)}');
    }
    if (input.findings.isEmpty) {
      buffer
        ..writeln()
        ..writeln(
          input.status == 'quiet'
              ? 'No findings were returned by this watcher.'
              : 'No findings were available because this watcher did not complete.',
        );
      continue;
    }
    for (final finding in input.findings) {
      buffer
        ..writeln()
        ..writeln('- **${_md(finding.title)}**')
        ..writeln('  - Subjects: ${finding.subjects.map(_code).join(', ')}')
        ..writeln(
          '  - References: ${finding.references.map((reference) => '[${_md(reference.label)}](${reference.url})').join(', ')}',
        )
        ..writeln('  - Marker: `${finding.marker}`');
    }
  }
  return buffer.toString();
}

String _heading(String watcher) => switch (watcher) {
      'dependencies' => 'Dependencies',
      'platforms' => 'Platforms',
      'peers' => 'Peers',
      _ => watcher,
    };

String _sourceDescription(String watcher) => switch (watcher) {
      'dependencies' =>
        'OSV against every committed lockfile, plus new releases of specifically reviewed dependencies.',
      'platforms' =>
        'Apple security releases, Android security bulletins, and narrow Linux credential-provider advisories.',
      'peers' =>
        'OSV advisories and recent GitHub issues, pull requests, and releases for the defined peer set.',
      _ => watcher,
    };

String _comment(String name, Map<String, Object> metadata) =>
    '<!-- $name: ${jsonEncode(metadata)} -->';

Map<String, Object?> _metadata(String content, String name) {
  final prefix = '<!-- $name: ';
  final firstLine = content.split('\n').first;
  if (!firstLine.startsWith(prefix) || !firstLine.endsWith(' -->')) {
    throw FormatException('missing $name metadata');
  }
  final raw = firstLine.substring(prefix.length, firstLine.length - 4);
  return _object(jsonDecode(raw), name);
}

Map<String, String> _options(List<String> arguments) {
  if (arguments.length.isOdd) {
    throw const FormatException('options must be --name value pairs');
  }
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    final option = arguments[index];
    if (!option.startsWith('--') || option.length == 2) {
      throw FormatException('invalid option: $option');
    }
    final name = option.substring(2);
    if (result.containsKey(name)) {
      throw FormatException('duplicate option: $option');
    }
    result[name] = arguments[index + 1];
  }
  return result;
}

String _required(Map<String, String> options, String name) {
  final value = options[name];
  if (value == null || value.isEmpty) {
    throw FormatException('missing --$name');
  }
  return value;
}

DateTime _timestamp(String value) {
  if (!RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('timestamp must include a timezone');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('invalid timestamp');
  return parsed.toUtc();
}

DateTime _timestampValue(Object? value, String label) {
  if (value is! String) throw FormatException('$label was not text');
  return _timestamp(value);
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label was not an object');
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

String _plain(String value, int maximum, String label) {
  final cleaned = value.trim();
  if (cleaned.isEmpty ||
      cleaned.length > maximum ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(cleaned)) {
    throw FormatException('$label was unsafe');
  }
  return cleaned;
}

String _status(Object? value, String watcher) {
  if (value is! String || !_statuses.contains(value)) {
    throw FormatException('$watcher report status was invalid');
  }
  return value;
}

bool _keybayActionUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
    return false;
  }
  final path = uri.pathSegments;
  if (path.length == 4 &&
      path[0] == 'danReynolds' &&
      path[1] == 'keybay' &&
      path[2] == 'issues') {
    return int.tryParse(path[3]) != null;
  }
  return path.length == 5 &&
      path[0] == 'danReynolds' &&
      path[1] == 'keybay' &&
      path[2] == 'security' &&
      path[3] == 'advisories' &&
      RegExp(r'^GHSA-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}-[23456789cfghjmpqrvwx]{4}$')
          .hasMatch(path[4]);
}

String _md(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('|', '\\|')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]')
    .replaceAll('*', '\\*')
    .replaceAll('_', '\\_')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _code(String value) => '`${value.replaceAll('`', "'")}`';

final class _SummaryRow {
  const _SummaryRow({
    required this.directory,
    required this.startedAt,
    required this.statuses,
    required this.assessmentStatus,
    required this.assessmentSummary,
    required this.actions,
  });

  final String directory;
  final DateTime startedAt;
  final Map<String, String> statuses;
  final String assessmentStatus;
  final String assessmentSummary;
  final List<({String label, String url})> actions;
}
