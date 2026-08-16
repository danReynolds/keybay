import 'dart:io';

enum DevicePlatform { android, ios, macos, linux }

enum EvidenceClass {
  hermetic,
  nativeHost,
  virtualDevice,
  physicalDevice,
}

extension EvidenceClassName on EvidenceClass {
  String get wireName => switch (this) {
        EvidenceClass.hermetic => 'hermetic',
        EvidenceClass.nativeHost => 'native-host',
        EvidenceClass.virtualDevice => 'virtual-device',
        EvidenceClass.physicalDevice => 'physical-device',
      };
}

final class SecurityScenario {
  const SecurityScenario({
    required this.id,
    required this.platform,
    required this.guarantees,
    required this.minimumEvidence,
    required this.destructive,
  });

  final String id;
  final DevicePlatform platform;
  final List<String> guarantees;
  final EvidenceClass minimumEvidence;
  final bool destructive;
}

const securityScenarios = <SecurityScenario>[
  SecurityScenario(
    id: 'KB-AND-001',
    platform: DevicePlatform.android,
    guarantees: ['KB-INV-005'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-AND-010',
    platform: DevicePlatform.android,
    guarantees: ['KB-INV-005'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-AND-011',
    platform: DevicePlatform.android,
    guarantees: ['KB-INV-001', 'KB-INV-002'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-AND-020',
    platform: DevicePlatform.android,
    guarantees: ['KB-INV-007'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-AND-030',
    platform: DevicePlatform.android,
    guarantees: ['KB-INV-003'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-IOS-001',
    platform: DevicePlatform.ios,
    guarantees: ['KB-INV-005'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-IOS-010',
    platform: DevicePlatform.ios,
    guarantees: ['KB-INV-005'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-IOS-020',
    platform: DevicePlatform.ios,
    guarantees: ['KB-INV-007'],
    minimumEvidence: EvidenceClass.physicalDevice,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-MAC-001',
    platform: DevicePlatform.macos,
    guarantees: ['KB-INV-005'],
    minimumEvidence: EvidenceClass.nativeHost,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-MAC-010',
    platform: DevicePlatform.macos,
    guarantees: ['KB-INV-001', 'KB-INV-002', 'KB-INV-005'],
    minimumEvidence: EvidenceClass.nativeHost,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-MAC-020',
    platform: DevicePlatform.macos,
    guarantees: ['KB-INV-007'],
    minimumEvidence: EvidenceClass.nativeHost,
    destructive: false,
  ),
  SecurityScenario(
    id: 'KB-MAC-030',
    platform: DevicePlatform.macos,
    guarantees: ['KB-INV-003', 'KB-INV-007'],
    minimumEvidence: EvidenceClass.nativeHost,
    destructive: false,
  ),
];

/// Current executable runner selections. This is execution wiring, not a
/// certification profile or a roadmap: only runnable scenarios appear here.
const scenarioSelections = <String, List<String>>{
  'android-baseline': [
    'KB-AND-001',
    'KB-AND-010',
    'KB-AND-011',
    'KB-AND-020',
  ],
  'android-tamper': [
    'KB-AND-001',
    'KB-AND-010',
    'KB-AND-011',
    'KB-AND-020',
    'KB-AND-030',
  ],
  'ios-baseline': ['KB-IOS-001', 'KB-IOS-010', 'KB-IOS-020'],
  'macos-baseline': ['KB-MAC-001', 'KB-MAC-010', 'KB-MAC-020'],
  'macos-tamper': [
    'KB-MAC-001',
    'KB-MAC-010',
    'KB-MAC-020',
    'KB-MAC-030',
  ],
};

SecurityScenario scenarioById(String id) => securityScenarios.singleWhere(
      (scenario) => scenario.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', 'unknown scenario'),
    );

List<SecurityScenario> scenariosForSelection(String selection) {
  final ids = scenarioSelections[selection];
  if (ids == null) {
    throw ArgumentError.value(selection, 'selection', 'unknown selection');
  }
  return [for (final id in ids) scenarioById(id)];
}

String executableInventoryMarkdown() {
  final buffer = StringBuffer()
    ..writeln('| ID | Platform | Guarantees | Minimum evidence | Destructive |')
    ..writeln('| --- | --- | --- | --- | --- |');
  for (final scenario in securityScenarios) {
    buffer.writeln(
      '| `${scenario.id}` | ${scenario.platform.name} | '
      '${scenario.guarantees.map((id) => '`$id`').join(', ')} | '
      '${scenario.minimumEvidence.wireName} | '
      '${scenario.destructive ? 'yes' : 'no'} |',
    );
  }
  return buffer.toString();
}

void main(List<String> args) {
  if (args.length == 1 && args.single == 'markdown') {
    stdout.write(executableInventoryMarkdown());
    return;
  }
  if (args.length == 2 && args.first == 'ids') {
    for (final scenario in scenariosForSelection(args[1])) {
      stdout.writeln(scenario.id);
    }
    return;
  }
  stderr.writeln('usage: catalog.dart markdown | ids SELECTION');
  exitCode = 64;
}
