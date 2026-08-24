import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String workflow;

  setUpAll(() async {
    workflow = await File(
      '.github/workflows/audit-release.yml',
    ).readAsString();
  });

  test('release audit requires successful full CI for the exact main commit',
      () {
    expect(workflow, contains(r'-f head_sha="$commit"'));
    expect(workflow, contains('-f branch=main'));
    expect(workflow, contains('-f status=completed'));
    expect(
      workflow,
      contains(
        '.event == "push" or .event == "workflow_dispatch"',
      ),
    );
    expect(workflow, contains('.conclusion == "success"'));
  });

  test('scheduled fuzz-only CI cannot satisfy the release audit', () {
    expect(workflow, isNot(contains('.event == "schedule"')));
  });
}
