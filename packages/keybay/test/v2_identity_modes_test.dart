@Tags(['unit'])
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test(
    'source and controlled AOT builds resolve the same declared identity',
    () async {
      final packageLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/keybay.dart'),
      );
      final packageConfig = await Isolate.packageConfig;
      expect(packageLibrary, isNotNull);
      expect(packageConfig, isNotNull);

      final packageRoot = File.fromUri(packageLibrary!).parent.parent;
      final compileHelper = File(
        '${packageRoot.path}${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}keybay_compile.dart',
      );
      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_identity_modes_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      final bin = Directory('${fixture.path}${Platform.pathSeparator}bin')
        ..createSync();
      File(
        '${fixture.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('''
name: identity_fixture
environment:
  sdk: ^3.6.0
keybay:
  application_id: dev.example.mode-fixture
''');
      final entrypoint = File('${bin.path}${Platform.pathSeparator}main.dart')
        ..writeAsStringSync('''
import 'dart:io';
import 'package:keybay/src/v2/application_identity.dart';

Future<void> main() async {
  try {
    final identity =
        await DartApplicationIdentityResolver.resolveCurrentProcess();
    stdout.write(identity.stableValue);
  } on ApplicationIdentityFailure catch (error) {
    stderr.write(error);
    exitCode = 2;
  }
}
''');
      final packagesArgument =
          '--packages=${File.fromUri(packageConfig!).path}';

      final source = await Process.run(Platform.resolvedExecutable, <String>[
        packagesArgument,
        entrypoint.path,
      ]);
      expect(source.exitCode, 0, reason: source.stderr as String?);
      expect(source.stdout, 'dev.example.mode-fixture');

      final output = File(
        '${fixture.path}${Platform.pathSeparator}'
        '${Platform.isWindows ? 'fixture.exe' : 'fixture'}',
      );
      final compilation = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          packagesArgument,
          compileHelper.path,
          entrypoint.path,
          '-o',
          output.path,
        ],
      );
      expect(compilation.exitCode, 0, reason: compilation.stderr as String?);
      expect(output.existsSync(), isTrue);

      final compiled = await Process.run(output.path, const <String>[]);
      expect(compiled.exitCode, 0, reason: compiled.stderr as String?);
      expect(compiled.stdout, source.stdout);

      if (Platform.isMacOS || Platform.isLinux) {
        final module = File('${fixture.path}/application.aot');
        final aotCompilation = await Process.run(Platform.resolvedExecutable, [
          packagesArgument,
          compileHelper.path,
          '--aot-snapshot',
          entrypoint.path,
          '-o',
          module.path,
        ]);
        expect(aotCompilation.exitCode, 0, reason: '${aotCompilation.stderr}');
        final runtime = File(
          Platform.resolvedExecutable,
        ).parent.uri.resolve('dartaotruntime');
        final aot = await Process.run(runtime.toFilePath(), [module.path]);
        expect(aot.exitCode, 0, reason: '${aot.stderr}');
        expect(aot.stdout, source.stdout);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'path activation resolves the activated package declaration',
    () async {
      final identityLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/src/v2/application_identity.dart'),
      );
      expect(identityLibrary, isNotNull);

      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_activation_mode_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      final application = Directory(
        '${fixture.path}${Platform.pathSeparator}application',
      )..createSync();
      final libraryDirectory = Directory(
        '${application.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}src${Platform.pathSeparator}v2',
      )..createSync(recursive: true);
      File.fromUri(identityLibrary!).copySync(
        '${libraryDirectory.path}${Platform.pathSeparator}'
        'application_identity.dart',
      );
      File(
        '${application.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('''
name: keybay_v2_activation_fixture
environment:
  sdk: '>=3.6.0 <4.0.0'
keybay:
  application_id: dev.example.activated-fixture
''');
      final executableDirectory = Directory(
        '${application.path}${Platform.pathSeparator}bin',
      )..createSync();
      File(
        '${executableDirectory.path}${Platform.pathSeparator}probe.dart',
      ).writeAsStringSync('''
import 'dart:io';
import 'package:keybay_v2_activation_fixture/src/v2/application_identity.dart';

Future<void> main() async {
  final identity =
      await DartApplicationIdentityResolver.resolveCurrentProcess();
  stdout.write('\${identity.stableValue}|\${identity.source.name}');
}
''');
      final cache = Directory(
        '${fixture.path}${Platform.pathSeparator}pub-cache',
      )..createSync();
      final environment = <String, String>{'PUB_CACHE': cache.path};

      final activation = await Process.run(
        Platform.resolvedExecutable,
        <String>[
          'pub',
          'global',
          'activate',
          '--source',
          'path',
          application.path,
        ],
        environment: environment,
      );
      expect(activation.exitCode, 0, reason: '${activation.stderr}');

      final activated = await Process.run(
        Platform.resolvedExecutable,
        const <String>[
          'pub',
          'global',
          'run',
          'keybay_v2_activation_fixture:probe',
        ],
        environment: environment,
      );
      expect(activated.exitCode, 0, reason: '${activated.stderr}');
      expect(
        '${activated.stdout}',
        endsWith('dev.example.activated-fixture|activatedPubspec'),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'dart install resolves the retained application declaration',
    () async {
      if (!_supportsDartInstall()) {
        markTestSkipped('dart install requires Dart 3.10 or later');
        return;
      }

      final identityLibrary = await Isolate.resolvePackageUri(
        Uri.parse('package:keybay/src/v2/application_identity.dart'),
      );
      expect(identityLibrary, isNotNull);

      final fixture = Directory.systemTemp.createTempSync(
        'keybay_v2_install_mode_',
      );
      addTearDown(() {
        if (fixture.existsSync()) fixture.deleteSync(recursive: true);
      });
      final application = Directory(
        '${fixture.path}${Platform.pathSeparator}application',
      )..createSync();
      final libraryDirectory = Directory(
        '${application.path}${Platform.pathSeparator}lib'
        '${Platform.pathSeparator}src${Platform.pathSeparator}v2',
      )..createSync(recursive: true);
      File.fromUri(identityLibrary!).copySync(
        '${libraryDirectory.path}${Platform.pathSeparator}'
        'application_identity.dart',
      );
      File(
        '${application.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('''
name: keybay_v2_install_fixture
environment:
  sdk: '>=3.10.0 <4.0.0'
executables:
  probe:
keybay:
  application_id: dev.example.installed-fixture
''');
      final executableDirectory = Directory(
        '${application.path}${Platform.pathSeparator}bin',
      )..createSync();
      File(
        '${executableDirectory.path}${Platform.pathSeparator}probe.dart',
      ).writeAsStringSync('''
import 'dart:io';
import 'package:keybay_v2_install_fixture/src/v2/application_identity.dart';

Future<void> main() async {
  final identity =
      await DartApplicationIdentityResolver.resolveCurrentProcess();
  stdout.write('\${identity.stableValue}|\${identity.source.name}');
}
''');

      final dartDataHome = Directory(
        '${fixture.path}${Platform.pathSeparator}dart-data',
      )..createSync();
      final cache = Directory(
        '${fixture.path}${Platform.pathSeparator}pub-cache',
      )..createSync();
      final environment = <String, String>{
        'DART_DATA_HOME': dartDataHome.path,
        'PUB_CACHE': cache.path,
      };
      final installation = await Process.run(
        Platform.resolvedExecutable,
        <String>['install', application.path],
        environment: environment,
      );
      expect(installation.exitCode, 0, reason: '${installation.stderr}');

      final installed = File(
        '${dartDataHome.path}${Platform.pathSeparator}install'
        '${Platform.pathSeparator}bin${Platform.pathSeparator}probe'
        '${Platform.isWindows ? '.bat' : ''}',
      );
      expect(installed.existsSync(), isTrue);
      final result = await Process.run(
        installed.path,
        const <String>[],
        environment: environment,
        runInShell: Platform.isWindows,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'dev.example.installed-fixture|dartInstallPubspec');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

bool _supportsDartInstall() {
  final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(Platform.version);
  if (match == null) return false;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 3 || (major == 3 && minor >= 10);
}
