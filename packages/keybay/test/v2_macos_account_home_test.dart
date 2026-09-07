@TestOn('mac-os')
@Tags(<String>['unit'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:keybay/src/v2/macos_account_home.dart';
import 'package:test/test.dart';

void main() {
  test('resolves one canonical absolute effective-account home', () {
    final home = resolveMacOSAccountHome();
    expect(home, startsWith('/'));
    expect(Directory(home).resolveSymbolicLinksSync(), home);
  });

  test('ignores HOME and CFFIXED_USER_HOME routing overrides', () async {
    final packageLibrary = await Isolate.resolvePackageUri(
      Uri.parse('package:keybay/keybay.dart'),
    );
    if (packageLibrary == null) fail('could not resolve the keybay package');
    final packageRoot = File.fromUri(packageLibrary).parent.parent;
    final worker = File(
      '${packageRoot.path}/test/support/v2_macos_account_home_worker.dart',
    );
    final hostileHome = '${Directory.systemTemp.path}/keybay-hostile-home';
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>[worker.path],
      workingDirectory: packageRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        'HOME': hostileHome,
        'CFFIXED_USER_HOME': hostileHome,
      },
    );

    expect(result.exitCode, 0, reason: result.stderr as String?);
    expect(result.stdout, resolveMacOSAccountHome());
    expect(result.stdout, isNot(hostileHome));
  });
}
