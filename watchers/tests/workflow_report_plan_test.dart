import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String workflow;

  setUpAll(() async {
    workflow = await File(
      '.github/workflows/security-watchers.yml',
    ).readAsString();
  });

  test('scheduled discovery cannot write repository state', () {
    final discovery = _job(workflow, 'report-discovery', 'report-publish');
    expect(discovery, contains('permissions:\n      contents: read'));
    expect(discovery, isNot(contains('issues: write')));
    expect(discovery, isNot(contains('pull-requests: write')));
    expect(discovery, contains('upload normalized discovery inputs'));
  });

  test('publisher can only create a report PR', () {
    final publisher = _job(workflow, 'report-publish', null);
    expect(publisher, contains('pull-requests: write'));
    expect(publisher, contains('watchers/report.dart create'));
    expect(publisher, contains('watchers/report.dart summary'));
    expect(publisher, contains('gh pr create'));
    expect(publisher, isNot(contains('gh issue create')));
    expect(publisher, isNot(contains('/security-advisories')));
  });

  test('required dependency check keeps its protected-branch name', () {
    final dependencies = _job(workflow, 'dependencies', 'report-discovery');
    expect(dependencies, contains('name: supply-chain / osv-scan'));
    expect(dependencies, contains('--fail-on-vuln=true'));
  });

  test('manual choices are the three unified watcher groups', () {
    expect(workflow, contains('          - dependencies'));
    expect(workflow, contains('          - platforms'));
    expect(workflow, contains('          - peers'));
    expect(workflow, isNot(contains('          - critical')));
  });
}

String _job(String workflow, String name, String? next) {
  final start = workflow.indexOf('  $name:');
  final end =
      next == null ? workflow.length : workflow.indexOf('\n  $next:', start);
  if (start < 0 || end < 0) throw StateError('workflow job not found: $name');
  return workflow.substring(start, end);
}
