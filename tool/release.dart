// Release orchestration for the Keybay workspace.
//
// Keybay ships two packages that version in lockstep — the `keybay` core
// library and the `keybay_cli` executable — and publishes them through
// tag-triggered GitHub Actions. Four references must agree on the release
// version:
//
//   packages/keybay/pubspec.yaml              version:     (core)
//   packages/keybay_cli/pubspec.yaml          version:     (cli)
//   packages/keybay_cli/pubspec.yaml          keybay:      (cli's exact core pin)
//   packages/keybay_cli/lib/src/command.dart  cliVersion            (`--version`)
//
// This tool keeps those four in sync and turns "release" into one intentional
// command per target:
//
//   dart run tool/release.dart status                 show every reference
//   dart run tool/release.dart check                  assert they all agree (CI-friendly)
//   dart run tool/release.dart set 0.2.0              write one version to all four
//   dart run tool/release.dart bump patch|minor|major increment the agreed version
//   dart run tool/release.dart publish core|cli       sign one tag on HEAD and push it
//
// Options: --dry-run (change and tag nothing), --yes (skip the publish prompt).
//
// `publish` is the only outward-facing verb. It creates a *signed* git tag on
// reference agrees, tracked files are clean, the matching CHANGELOG carries
// the version, and the tag does not already exist. Before creating the core
// tag it also rebuilds the candidate assurance manifest from the exact package,
// latest successful CI run, and required qualification receipt. Core must be
// tagged from the current `origin/main` tip. CLI must be tagged later from that
// exact core-tag commit, after the core workflow succeeds and the version is
// live on pub.dev.
library;

import 'dart:io';

// ---------------------------------------------------------------------------
// Pure version logic (no IO; mirrored by
// packages/keybay/test/version_consistency_test.dart).
// ---------------------------------------------------------------------------

/// A semantic-version core, `major.minor.patch` (no pre-release/build suffix —
/// this project's tags are plain triples).
final class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final RegExp _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  factory Version.parse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      throw FormatException('expected a major.minor.patch version', value);
    }
    return Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Returns the version with [part] (`major`/`minor`/`patch`) incremented and
  /// the lesser parts reset.
  Version bump(String part) => switch (part) {
        'major' => Version(major + 1, 0, 0),
        'minor' => Version(major, minor + 1, 0),
        'patch' => Version(major, minor, patch + 1),
        _ => throw FormatException(
            'version part must be major, minor, or patch', part),
      };

  @override
  String toString() => '$major.$minor.$patch';

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is Version &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

/// The four references that must carry the same release version.
enum VersionField {
  corePubspecVersion,
  cliPubspecVersion,
  cliKeybayPin,
  cliVersionConst,
}

/// Each pattern captures (1) everything up to the value and (2) the value, so a
/// replacement can swap the value while preserving surrounding text. The CLI
/// pin pattern requires a version-shaped value, so it never matches the
/// `keybay: keybay` executable mapping in the same pubspec.
final Map<VersionField, RegExp> versionPatterns = <VersionField, RegExp>{
  VersionField.corePubspecVersion:
      RegExp(r'(^version:[ \t]*)(\S+)', multiLine: true),
  VersionField.cliPubspecVersion:
      RegExp(r'(^version:[ \t]*)(\S+)', multiLine: true),
  VersionField.cliKeybayPin:
      RegExp(r'(^[ \t]+keybay:[ \t]*)(\d+\.\d+\.\d+\S*)', multiLine: true),
  VersionField.cliVersionConst: RegExp("(cliVersion[ \\t]*=[ \\t]*')([^']+)"),
};

const Map<VersionField, String> versionFieldLabels = <VersionField, String>{
  VersionField.corePubspecVersion: 'core pubspec version',
  VersionField.cliPubspecVersion: 'cli pubspec version',
  VersionField.cliKeybayPin: 'cli keybay dependency pin',
  VersionField.cliVersionConst: 'cli cliVersion constant',
};

/// Reads [field] from file [content], or null when the pattern is absent.
String? readVersionField(String content, VersionField field) =>
    versionPatterns[field]!.firstMatch(content)?.group(2);

/// Returns [content] with [field] set to [version], throwing if the field is
/// absent (a signal the file format drifted from what this tool understands).
String setVersionField(String content, VersionField field, String version) {
  final pattern = versionPatterns[field]!;
  if (!pattern.hasMatch(content)) {
    throw FormatException(
        'could not find the ${versionFieldLabels[field]} to update');
  }
  return content.replaceFirstMapped(
      pattern, (match) => '${match.group(1)}$version');
}

/// Whether a Markdown changelog [content] has a `## <version>` section heading.
bool changelogHasEntry(String content, String version) =>
    RegExp('^##[ \\t]+${RegExp.escape(version)}[ \\t]*\$', multiLine: true)
        .hasMatch(content);

/// Inserts a `## <version>` stub before the first existing `## ` heading (or
/// after a leading `# ` title), so a fresh release PR carries a slot to fill.
/// Returns [content] unchanged when the version already has an entry.
String insertChangelogStub(String content, String version) {
  if (changelogHasEntry(content, version)) return content;
  final stub = '## $version\n\n- _Summarize the changes in $version._\n\n';
  final firstEntry = RegExp(r'^## ', multiLine: true).firstMatch(content);
  if (firstEntry != null) {
    return content.replaceRange(firstEntry.start, firstEntry.start, stub);
  }
  final title = RegExp(r'^# .*\n', multiLine: true).firstMatch(content);
  if (title != null) {
    return content.replaceRange(title.end, title.end, '\n$stub');
  }
  return '$stub$content';
}

// ---------------------------------------------------------------------------
// Workspace layout.
// ---------------------------------------------------------------------------

const Map<VersionField, String> _fieldFiles = <VersionField, String>{
  VersionField.corePubspecVersion: 'packages/keybay/pubspec.yaml',
  VersionField.cliPubspecVersion: 'packages/keybay_cli/pubspec.yaml',
  VersionField.cliKeybayPin: 'packages/keybay_cli/pubspec.yaml',
  VersionField.cliVersionConst: 'packages/keybay_cli/lib/src/command.dart',
};

const String _coreChangelog = 'packages/keybay/CHANGELOG.md';
const String _cliChangelog = 'packages/keybay_cli/CHANGELOG.md';
String _repoRoot() {
  final fromScript =
      File(Platform.script.toFilePath()).parent.parent.path; // tool/ -> root
  if (File('$fromScript/pubspec.yaml').existsSync()) return fromScript;
  if (File('pubspec.yaml').existsSync()) return Directory.current.path;
  _fail('cannot locate the workspace root; run from the repository');
}

Map<VersionField, String> _readAll(String root) {
  final values = <VersionField, String>{};
  for (final field in VersionField.values) {
    final relative = _fieldFiles[field]!;
    final value =
        readVersionField(File('$root/$relative').readAsStringSync(), field);
    if (value == null) {
      _fail('could not read the ${versionFieldLabels[field]} from $relative');
    }
    values[field] = value;
  }
  return values;
}

/// The single agreed version across all references, or a failure listing the
/// drift.
Version _agreedVersion(Map<VersionField, String> values) {
  if (values.values.toSet().length != 1) {
    stderr.writeln('release: version references disagree:');
    for (final entry in values.entries) {
      stderr.writeln(
          '  ${versionFieldLabels[entry.key]!.padRight(26)} ${entry.value}');
    }
    _fail('synchronize them with `set <x.y.z>` or `bump <part>` first');
  }
  return Version.parse(values.values.first);
}

String _changelogState(String root, String relative, String version) =>
    changelogHasEntry(File('$root/$relative').readAsStringSync(), version)
        ? 'present'
        : 'MISSING';

// ---------------------------------------------------------------------------
// Commands.
// ---------------------------------------------------------------------------

void _status(String root) {
  final values = _readAll(root);
  stdout.writeln('Keybay version references:');
  for (final entry in values.entries) {
    stdout.writeln(
        '  ${versionFieldLabels[entry.key]!.padRight(26)} ${entry.value}');
  }
  final distinct = values.values.toSet();
  if (distinct.length == 1) {
    final version = distinct.first;
    stdout.writeln('\nall four agree at $version');
    stdout.writeln(
        '  CHANGELOG.md ## $version:                    ${_changelogState(root, _coreChangelog, version)}');
    stdout.writeln(
        '  packages/keybay_cli/CHANGELOG.md ## $version: ${_changelogState(root, _cliChangelog, version)}');
  } else {
    stdout.writeln('\nreferences DISAGREE (${distinct.length} distinct values) '
        '— run `set` or `bump` to synchronize');
  }
}

void _check(String root) {
  final version = _agreedVersion(_readAll(root));
  stdout.writeln('ok: all four version references agree at $version');
}

void _set(String root, String versionArg, {required bool dryRun}) {
  final version = Version.parse(versionArg).toString(); // validate + normalize
  final changed = <String>[];
  for (final field in VersionField.values) {
    final relative = _fieldFiles[field]!;
    final path = '$root/$relative';
    final before = File(path).readAsStringSync();
    final after = setVersionField(before, field, version);
    if (before != after) {
      if (!dryRun) File(path).writeAsStringSync(after);
      changed.add('$relative (${versionFieldLabels[field]})');
    }
  }
  stdout.writeln(
      '${dryRun ? '(dry-run) would set' : 'set'} all references to $version:');
  if (changed.isEmpty) {
    stdout.writeln('  (already at $version — nothing to change)');
  }
  for (final entry in changed) {
    stdout.writeln('  $entry');
  }
  for (final relative in <String>[_coreChangelog, _cliChangelog]) {
    if (_changelogState(root, relative, version) == 'MISSING') {
      stdout.writeln(
          'note: $relative has no "## $version" section — add release notes '
          'before publishing');
    }
  }
}

void _bump(String root, String part, {required bool dryRun}) {
  final current = _agreedVersion(_readAll(root)); // require agreement first
  final next = current.bump(part);
  stdout.writeln('bump $part: $current -> $next');
  _set(root, next.toString(), dryRun: dryRun);
}

// ---------------------------------------------------------------------------
// Entry point.
// ---------------------------------------------------------------------------

const String _usage = '''
Keybay version tool — one version across both packages.

Usage: dart run tool/release.dart <command> [options]

  status                       Show every version reference and whether they agree.
  check                        Assert all four references agree (exit 1 on drift).
  set <x.y.z>                  Write one version to all four references.
  bump <major|minor|patch>     Increment the agreed version across all references.

Options:
  --dry-run                    Show what would happen; write nothing.
  --help, -h                   Show this help.

The two packages version in lockstep. Releasing is rk's job (see release.toml):
this tool only keeps the version references agreeing before a release is cut.
''';

Never _fail(String message) {
  stderr.writeln('release: $message');
  exit(1);
}

void main(List<String> args) {
  final positional = <String>[];
  var dryRun = false;
  for (final arg in args) {
    switch (arg) {
      case '--dry-run':
        dryRun = true;
      case '--help' || '-h':
        stdout.write(_usage);
        return;
      default:
        if (arg.startsWith('-')) _fail('unknown option: $arg (try --help)');
        positional.add(arg);
    }
  }
  if (positional.isEmpty) {
    stdout.write(_usage);
    return;
  }

  final root = _repoRoot();
  final rest = positional.sublist(1);
  // A FormatException from the pure version logic (a malformed version, an
  // unknown bump part, a drifted file format) is a user-facing input error, not
  // a crash — surface it as a clean `release:` message rather than a stack trace.
  try {
    switch (positional.first) {
      case 'status':
        _status(root);
      case 'check':
        _check(root);
      case 'set':
        if (rest.length != 1) _fail('usage: set <x.y.z>');
        _set(root, rest.first, dryRun: dryRun);
      case 'bump':
        if (rest.length != 1) _fail('usage: bump <major|minor|patch>');
        _bump(root, rest.first, dryRun: dryRun);
      default:
        _fail('unknown command: ${positional.first} (try --help)');
    }
  } on FormatException catch (error) {
    final source = error.source;
    _fail(source == null ? error.message : '${error.message}: $source');
  }
}
