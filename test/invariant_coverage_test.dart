@Tags(['unit'])
library;

import 'dart:io';

import 'package:test/test.dart';

/// The one-page model's promises decompose into numbered invariants
/// (doc/design.md). An invariant with no executable falsifier is a claim
/// outrunning its evidence; this test refuses that state, in both directions.
void main() {
  test('every declared KB-INV invariant has an executable falsifier', () {
    final design = File('doc/design.md').readAsStringSync();
    // \d+ (not \d{3}) so a future KB-INV-1000 is never truncated to a
    // phantom KB-INV-100; matches the pattern the receipt test uses.
    final idPattern = RegExp(r'KB-INV-\d+');
    final declared =
        idPattern.allMatches(design).map((match) => match.group(0)!).toSet();
    expect(declared, isNotEmpty,
        reason: 'doc/design.md must declare KB-INV-* invariants');

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
      referenced.addAll(idPattern
          .allMatches(file.readAsStringSync())
          .map((match) => match.group(0)!));
    }

    final unfalsified = declared.difference(referenced);
    expect(
      unfalsified,
      isEmpty,
      reason: 'invariants with no test or device scenario referencing them: '
          '${unfalsified.toList()..sort()} — add the falsifier or remove the '
          'claim from design.md',
    );

    final undeclared = referenced.difference(declared);
    expect(
      undeclared,
      isEmpty,
      reason: 'executable references to invariants design.md does not '
          'declare: ${undeclared.toList()..sort()}',
    );
  });
}
