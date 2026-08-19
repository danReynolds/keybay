import 'dart:io';

import 'release.dart' as release_tool;

/// Pure-logic checks for the version tool.
///
/// The release-policy tests that used to live here — signing, tag ordering,
/// publish sequencing — went with the release commands: rk owns that now, and
/// its own suite covers it.
void main() {
  if (release_tool.changelogHasEntry(
      '# Changelog\n\n## 1.2.3-beta\n', '1.2.3')) {
    _fail('a prerelease changelog heading satisfied a stable release');
  }
  if (!release_tool.changelogHasEntry('# Changelog\n\n## 1.2.3\n', '1.2.3')) {
    _fail('an exact stable changelog heading was rejected');
  }

  final stub =
      release_tool.insertChangelogStub('# Changelog\n\n## 1.0.0\n', '1.1.0');
  if (!release_tool.changelogHasEntry(stub, '1.1.0')) {
    _fail('an inserted changelog stub was not recognized');
  }

  for (final field in release_tool.versionPatterns.keys) {
    final source = switch (field) {
      release_tool.VersionField.corePubspecVersion ||
      release_tool.VersionField.cliPubspecVersion =>
        'name: x\nversion: 1.0.0\n',
      release_tool.VersionField.cliKeybayPin =>
        'dependencies:\n  keybay: 1.0.0\n',
      release_tool.VersionField.cliVersionConst =>
        "const String cliVersion = '1.0.0';\n",
    };
    final written = release_tool.setVersionField(source, field, '2.0.0');
    if (!written.contains('2.0.0')) {
      _fail('setVersionField did not write \$field');
    }
  }

  stdout.writeln('version tool checks passed');
}

Never _fail(String message) {
  stderr.writeln('test_release: \$message');
  exit(1);
}
