import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String workflow;

  setUpAll(() async {
    workflow = await File(
      '.github/workflows/audit-cli-release.yml',
    ).readAsString();
  });

  test('published verification key matches both release audits', () {
    final key = RegExp(r'ssh-ed25519 [A-Za-z0-9+/=]+');
    final keys = {
      for (final path in [
        'SECURITY.md',
        '.github/workflows/audit-release.yml',
        '.github/workflows/audit-cli-release.yml',
      ])
        for (final match in key.allMatches(File(path).readAsStringSync()))
          match[0],
    };
    expect(keys, hasLength(1));
    expect(
      File('SECURITY.md').readAsStringSync(),
      contains('SHA256:4ozSnfVaMzZ/qrzo51I8FPKawmZSIojAB5Ll+qhguFM'),
    );
  });

  test('the signed tag binds the manifest, archives and formula', () {
    expect(workflow, contains(r'git -C source verify-tag "$tag"'));
    expect(workflow, contains('release-manifest-sha256'));
    expect(workflow, contains('sha256sum --check --strict'));
    expect(workflow, contains('.homebrew.sha256'));
    expect(workflow, contains(r'gh release verify "$AUDIT_TAG"'));
  });

  test('the newest CLI release and its formula are re-checked daily', () {
    expect(workflow, contains('schedule:'));
    expect(workflow, contains('startswith("keybay_cli-v")'));
    expect(workflow, contains(r'"$AUDIT_TAG" != "$NEWEST_TAG"'));
  });

  test('event data reaches shell only through environment variables', () {
    final allowed = RegExp(
      r'^\s*(group|if|GH_TOKEN|EVENT_NAME|REQUESTED_TAG):',
    );
    for (final line in workflow.split('\n')) {
      if (line.contains(r'${{')) expect(line, matches(allowed));
    }
  });
}
