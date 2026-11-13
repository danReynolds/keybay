import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory commands;
  late File brewLog;

  void executable(String name, String body) {
    final file = File('${commands.path}/$name');
    file.writeAsStringSync('#!/bin/bash\nset -eu\n$body\n');
    Process.runSync('/bin/chmod', ['+x', file.path]);
  }

  Future<ProcessResult> install({Map<String, String> environment = const {}}) =>
      Process.run(
        '/bin/bash',
        ['tool/install_cli_hardware_build_deps.sh'],
        environment: {
          'PATH': commands.path,
          'BREW_LOG': brewLog.path,
          'HOMEBREW_NO_INSTALL_UPGRADE': '',
          ...environment,
        },
      );

  List<String> calls() => brewLog.readAsLinesSync();

  setUp(() {
    commands = Directory.systemTemp.createTempSync('keybay-build-deps-test-');
    brewLog = File('${commands.path}/brew.log');
    executable('uname', 'printf "Darwin\\n"');
    executable('brew', r'''
printf '%s\n' "$*" >> "$BREW_LOG"
if [[ "$*" == 'install libfido2' && -n "${HOMEBREW_NO_INSTALL_UPGRADE:-}" ]]; then exit 43; fi
if [[ "$*" == 'install libfido2' && "${FAKE_FIDO_FAILURE:-}" == 1 ]]; then exit 42; fi
if [[ "$*" == '--prefix libfido2' ]]; then printf '/fake/libfido2\n'; fi
''');
    executable('otool', r'''
if [[ "${FAKE_CRYPTO_LINK_MISSING:-}" == 1 ]]; then
  printf '/fake/libfido2/lib/libfido2.1.dylib\n'
else
  printf '/fake/openssl/lib/libcrypto.4.dylib\n'
fi
''');
    Link('${commands.path}/grep').createSync('/usr/bin/grep');
  });

  tearDown(() => commands.deleteSync(recursive: true));

  test(
    'reuses runner build tools while refreshing libfido2 normally',
    () async {
      executable('cmake', r'printf "cmake version 4.4.2\n"');
      executable('pkg-config', 'exit 0');
      final result = await install();
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(calls(), [
        'update --quiet',
        'install libfido2',
        '--prefix libfido2',
      ]);
    },
  );

  test('installs missing build tools without omitting libfido2', () async {
    final result = await install();
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(calls(), [
      'update --quiet',
      'install cmake',
      'install pkg-config',
      'install libfido2',
      '--prefix libfido2',
    ]);
  });

  for (final version in ['3.9.0', '3.21.9', 'unknown']) {
    test('updates unsupported CMake $version', () async {
      executable('cmake', 'printf "cmake version $version\\n"');
      executable('pkg-config', 'exit 0');
      final result = await install();
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(calls(), [
        'update --quiet',
        'install cmake',
        'install libfido2',
        '--prefix libfido2',
      ]);
    });
  }

  test('accepts the minimum supported CMake', () async {
    executable('cmake', r'printf "cmake version 3.22.0\n"');
    executable('pkg-config', 'exit 0');
    final result = await install();
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(calls(), [
      'update --quiet',
      'install libfido2',
      '--prefix libfido2',
    ]);
  });

  test('libfido2 installation failures remain fatal', () async {
    executable('cmake', r'printf "cmake version 4.4.2\n"');
    executable('pkg-config', 'exit 0');
    final result = await install(environment: {'FAKE_FIDO_FAILURE': '1'});
    expect(result.exitCode, 42);
    expect(calls(), ['update --quiet', 'install libfido2']);
  });

  test('missing libcrypto linkage still fails qualification', () async {
    executable('cmake', r'printf "cmake version 4.4.2\n"');
    executable('pkg-config', 'exit 0');
    final result = await install(
      environment: {'FAKE_CRYPTO_LINK_MISSING': '1'},
    );
    expect(result.exitCode, isNot(0));
    expect(calls().contains('install libfido2'), isTrue);
  });
}
