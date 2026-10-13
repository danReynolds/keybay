import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _releaseKey =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtnuwBbMwdKZu2YlUnDdhW7t0bp7JlCjUZR8/JOQae6';

void main() {
  late String workflow;

  setUpAll(() async {
    workflow = await File(
      '.github/workflows/audit-cli-release.yml',
    ).readAsString();
  });

  test('each published copy of the release key is the same key', () {
    final key = RegExp(r'ssh-ed25519 [A-Za-z0-9+/=]+');
    for (final path in [
      'SECURITY.md',
      '.github/workflows/audit-release.yml',
      '.github/workflows/audit-cli-release.yml',
    ]) {
      final found = {
        for (final match in key.allMatches(File(path).readAsStringSync()))
          match[0],
      };
      expect(found, {_releaseKey}, reason: path);
    }
    final digest = sha256.convert(base64.decode(_releaseKey.split(' ')[1]));
    final fingerprint = base64.encode(digest.bytes).replaceAll('=', '');
    expect(
      File('SECURITY.md').readAsStringSync(),
      contains('SHA256:$fingerprint'),
    );
  });

  test('the signed tag binds the manifest, archives and formula', () {
    expect(workflow, contains(r'git -C source verify-tag "$tag"'));
    expect(workflow, contains('release-manifest-sha256'));
    expect(workflow, contains('sha256sum --check --strict'));
    expect(workflow, contains('.homebrew.sha256'));
    expect(workflow, contains(r'gh release verify-asset "$AUDIT_TAG" "$file"'));
  });

  test('the newest CLI release and its formula are re-checked daily', () {
    expect(workflow, contains('schedule:'));
    expect(workflow, contains('max_by('));
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
