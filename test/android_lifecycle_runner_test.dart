import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Android continuity requires correlated native exit and cleanup', () {
    final result = Process.runSync('python3', [
      '-B',
      '-c',
      r'''
import importlib.util, json, sys
sys.path.insert(0, "tool/device_security")
spec = importlib.util.spec_from_file_location('lifecycle', 'tool/device_security/android_lifecycle.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
receipt = {'kind': 'keybay-mobile-lifecycle', 'nonce': 'a' * 64,
           'subject': 'git-commit:' + 'b' * 40, 'phase': 'reopen',
           'status': 'pass', 'reason': 'completed', 'mode': 'process', 'build': '101', 'pid': 123}
assert module.verify_receipt(receipt, receipt['nonce'], receipt['subject'], 'reopen', 'process', '101') == 123
history = """ACTIVITY MANAGER PROCESS EXIT INFO (dumpsys activity exit-info)
  ApplicationExitInfo #0:
    timestamp=2026-09-05 22:00:00.000 pid=123 realUid=10456 packageUid=10456 definingUid=10456 user=0
    process=dev.keybay.securityharness reason=1 (EXIT SELF) subreason=0 (UNKNOWN) status=0
    importance=100 pss=0 rss=0
"""
module.verify_exit(history, 123, 10456, 0)
cases = []
for key, value in [('nonce', 'c' * 64), ('subject', 'git-commit:' + 'd' * 40), ('phase', 'seed'),
                   ('mode', 'upgrade'), ('build', '102'), ('pid', True), ('pid', 0), ('status', 'fail')]:
    bad = dict(receipt, **{key: value})
    cases.append(lambda bad=bad: module.verify_receipt(bad, receipt['nonce'], receipt['subject'], 'reopen', 'process', '101'))
seed = {'build_number': '101', 'aot_sha256': 'a', 'package': module.PACKAGE, 'signer_sha256': 'c'}
reopen = dict(seed, build_number='102', aot_sha256='b')
module.verify_upgrade(seed, reopen, ('package', 'signer_sha256'))
for key, value in [('build_number', '101'), ('aot_sha256', 'a'), ('package', 'other'), ('signer_sha256', 'd')]:
    bad = dict(reopen, **{key: value})
    cases.append(lambda bad=bad: module.verify_upgrade(seed, bad, ('package', 'signer_sha256')))
for text in ('', history + history,
             history.replace('pid=123', 'pid=124'),
             history.replace('reason=1', 'reason=5'),
             history.replace('status=0', 'status=1'),
             history.replace('packageUid=10456', 'packageUid=10457'),
             history.replace('realUid=10456', 'realUid=10457'),
             history.replace('user=0', 'user=10'),
             history.replace('process=dev.keybay.securityharness', 'process=unrelated.app')):
    cases.append(lambda text=text: module.verify_exit(text, 123, 10456, 0))
clean = 'no_backup\nno_backup/keybay-lifecycle-result.json\nno_backup/keybay-v2/keybay.v2.lock\n'
module.verify_cleanup(clean)
for leftover in ('keybay-lifecycle-control.json', 'keybay-v2/keybay.v2.store', 'keybay-v2/keybay.v2.stage'):
    cases.append(lambda leftover=leftover: module.verify_cleanup(clean + 'no_backup/' + leftover))
cases.append(lambda: module.verify_cleanup(''))
for case in cases:
    try:
        case()
    except ValueError:
        continue
    raise AssertionError('accepted invalid evidence')
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
