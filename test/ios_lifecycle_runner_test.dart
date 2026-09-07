import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('iOS continuity rejects stale receipts and launcher-only success', () {
    final result = Process.runSync('python3', [
      '-B',
      '-c',
      r'''
import copy, importlib.util, sys
sys.path.insert(0, "tool/device_security")
spec = importlib.util.spec_from_file_location('lifecycle', 'tool/device_security/ios_lifecycle.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
command = {'info': {'outcome': 'success'}, 'result': {
    'process': {'processIdentifier': 123}, 'terminationResult': {'exitCode': 0}}}
receipt = {'kind': 'keybay-mobile-lifecycle', 'nonce': 'a' * 64,
           'subject': 'git-commit:' + 'b' * 40, 'phase': 'reopen',
           'status': 'pass', 'reason': 'completed', 'mode': 'process', 'build': '101', 'pid': 123}
def verify(c, r):
    return module.verify_phase(c, r, receipt['nonce'], receipt['subject'], 'reopen')
assert verify(command, receipt) == 123
bad_commands = []
for code in (None, 1, False, '0'):
    bad = copy.deepcopy(command)
    bad['result']['terminationResult']['exitCode'] = code
    bad_commands.append(bad)
for pid in (None, 0, True, '123'):
    bad = copy.deepcopy(command)
    bad['result']['process']['processIdentifier'] = pid
    bad_commands.append(bad)
bad = copy.deepcopy(command)
bad['info']['outcome'] = 'failure'
bad_commands.extend([bad, {'info': {'outcome': 'success'}}, {}])
cases = [(bad, receipt) for bad in bad_commands]
for field, wrong in [('phase', 'seed'), ('nonce', 'c' * 64),
                     ('subject', 'git-commit:' + 'd' * 40), ('status', 'fail'),
                     ('reason', 'cleanup_failed'), ('kind', 'unrelated'), ('build', '102'), ('mode', 'upgrade'), ('pid', 124)]:
    cases.append((command, dict(receipt, **{field: wrong})))
cases.append((command, {}))
for c, r in cases:
    try:
        verify(c, r)
    except ValueError:
        continue
    raise AssertionError('accepted incomplete or mismatched evidence')
module.verify_cleanup([{'relativePath': 'keybay-lifecycle-result.json'},
                       {'relativePath': 'keybay-v2/keybay.v2.lock'}])
for leftover in ('keybay-lifecycle-control.json', 'keybay-v2/keybay.v2.store',
                 'keybay-v2/keybay.v2.stage'):
    try:
        module.verify_cleanup([{'relativePath': 'keybay-lifecycle-result.json'},
                               {'relativePath': leftover}])
    except ValueError:
        continue
    raise AssertionError('accepted leftover fixture data')
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
