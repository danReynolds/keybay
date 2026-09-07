@Tags(['unit'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every design invariant has an executable reference or a visible pending
/// qualification obligation. References establish coverage, not a passing run
/// or proof of every platform/lifecycle dimension of the invariant.
void main() {
  test('every invariant has executable coverage or a documented open gate', () {
    final design = File('doc/design.md').readAsStringSync();
    final suite = File('doc/device-security-suite.md').readAsStringSync();
    // \d+ (not \d{3}) so a future KB-INV-1000 is never truncated to a
    // phantom KB-INV-100; matches the device-report test pattern.
    final idPattern = RegExp(r'KB-INV-\d+');
    final declared = idPattern
        .allMatches(design)
        .map((match) => match.group(0)!)
        .toSet();
    expect(
      declared,
      isNotEmpty,
      reason: 'doc/design.md must declare KB-INV-* invariants',
    );

    final executableRoots = [
      Directory('packages/keybay/test'),
      Directory('packages/keybay_cli/test'),
      Directory('example_flutter/integration_test'),
    ];
    final files = <File>[
      File('tool/device_security/catalog.dart'),
      for (final root in executableRoots)
        ...root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
    ];
    final referenced = <String>{};
    for (final file in files) {
      referenced.addAll(
        idPattern
            .allMatches(file.readAsStringSync())
            .map((match) => match.group(0)!),
      );
    }

    final pendingLine = RegExp(
      r'^Pending executable V2 coverage: (.+)\.$',
      multiLine: true,
    ).firstMatch(suite);
    final pending = idPattern
        .allMatches(pendingLine?.group(1) ?? '')
        .map((match) => match.group(0)!)
        .toSet();
    expect(
      pending.intersection(referenced),
      isEmpty,
      reason: 'remove stale pending entries when executable coverage is added',
    );

    final unfalsified = declared.difference(referenced.union(pending));
    expect(
      unfalsified,
      isEmpty,
      reason:
          'invariants with neither executable coverage nor an explicit open '
          'qualification gate: ${unfalsified.toList()..sort()}',
    );

    final undeclared = referenced.union(pending).difference(declared);
    expect(
      undeclared,
      isEmpty,
      reason:
          'executable references to invariants design.md does not '
          'declare: ${undeclared.toList()..sort()}',
    );
  });
}
