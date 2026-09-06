@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:keybay/src/v2/application_identity.dart';
import 'package:test/test.dart';

void main() {
  group('application ID grammar', () {
    for (final value in <String>['A', 'A${'z' * 119}', 'Dev.Example_app-1']) {
      test('accepts ${value.length} canonical ASCII characters', () {
        final identity = ApplicationIdentity(
          stableValue: value,
          source: ApplicationIdentitySource.test,
          assurance: ApplicationIdentityAssurance.namespaceOnly,
        );

        expect(identity.stableValue, value);
      });
    }

    for (final value in <String>[
      '',
      'A${'z' * 120}',
      '.leading',
      '-leading',
      '_leading',
      'dev/example',
      r'dev\example',
      'dev:example',
      'dev%example',
      'dev example',
      'dev\nexample',
      'dév.example',
    ]) {
      test('rejects non-canonical value ${jsonEncode(value)}', () {
        expect(
          () => ApplicationIdentity(
            stableValue: value,
            source: ApplicationIdentitySource.test,
            assurance: ApplicationIdentityAssurance.namespaceOnly,
          ),
          throwsA(_failure(ApplicationIdentityFailureCode.invalidDeclaration)),
        );
      });
    }
  });

  group('source pubspec declaration', () {
    test('accepts the narrow block grammar', () {
      final fixture = _SourceFixture.create(
        pubspec:
            'name: example\r\n'
            '\r\n'
            'keybay: # stable application namespace\r\n'
            '  # Kept outside Dart business logic.\r\n'
            '  application_id: Dev.Example_app-1  \r\n',
      );
      addTearDown(fixture.dispose);

      final identity = fixture.resolver().resolve();

      expect(identity.stableValue, 'Dev.Example_app-1');
      expect(identity.source, ApplicationIdentitySource.sourcePubspec);
      expect(identity.assurance, ApplicationIdentityAssurance.namespaceOnly);
    });

    final malformed = <String, String>{
      'missing keybay section': 'name: example\n',
      'missing application ID': 'keybay:\n  other: value\n',
      'one-space indentation': 'keybay:\n application_id: dev.example\n',
      'four-space indentation': 'keybay:\n    application_id: dev.example\n',
      'tab indentation': 'keybay:\n\tapplication_id: dev.example\n',
      'quoted scalar': 'keybay:\n  application_id: "dev.example"\n',
      'inline map': 'keybay: {application_id: dev.example}\n',
      'block scalar': 'keybay:\n  application_id: >\n    dev.example\n',
      'trailing comment':
          'keybay:\n  application_id: dev.example # not in the grammar\n',
      'duplicate section':
          'keybay:\n  application_id: dev.one\n'
          'keybay:\n  application_id: dev.two\n',
      'duplicate application ID':
          'keybay:\n'
          '  application_id: dev.one\n'
          '  application_id: dev.two\n',
    };

    for (final entry in malformed.entries) {
      test('fails closed for ${entry.key}', () {
        final fixture = _SourceFixture.create(pubspec: entry.value);
        addTearDown(fixture.dispose);

        expect(
          fixture.resolver().resolve,
          throwsA(isA<ApplicationIdentityFailure>()),
        );
      });
    }

    test('rejects a quoted duplicate of the keybay section', () {
      final fixture = _SourceFixture.create(
        pubspec:
            'keybay:\n'
            '  application_id: dev.one\n'
            '"keybay":\n'
            '  application_id: dev.two\n',
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver().resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.invalidDeclaration)),
      );
    });

    test('rejects a quoted duplicate of application_id', () {
      final fixture = _SourceFixture.create(
        pubspec:
            'keybay:\n'
            '  application_id: dev.one\n'
            '  "application_id": dev.two\n',
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver().resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.invalidDeclaration)),
      );
    });

    test('uses the source-owning pubspec and never the current directory', () {
      final owner = _SourceFixture.create(
        pubspec: 'keybay:\n  application_id: dev.owner\n',
      );
      final decoy = Directory.systemTemp.createTempSync('keybay-cwd-decoy-');
      File(
        '${decoy.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('keybay:\n  application_id: dev.decoy\n');
      addTearDown(owner.dispose);
      addTearDown(() => decoy.deleteSync(recursive: true));

      final priorCurrent = Directory.current.path;
      ApplicationIdentity identity;
      try {
        Directory.current = decoy;
        identity = owner.resolver().resolve();
      } finally {
        Directory.current = priorCurrent;
      }

      expect(identity.stableValue, 'dev.owner');
    });

    test('requires an embedded declaration to match source metadata', () {
      final fixture = _SourceFixture.create(
        pubspec: 'keybay:\n  application_id: dev.source\n',
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver(embeddedApplicationId: 'dev.other').resolve,
        throwsA(
          _failure(ApplicationIdentityFailureCode.conflictingDeclarations),
        ),
      );
    });

    test('rejects metadata over the byte limit before parsing', () {
      final fixture = _SourceFixture.createBytes(
        List<int>.filled(
          DartApplicationIdentityResolver.maximumPubspecBytes + 1,
          0x20,
        ),
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver().resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.metadataTooLarge)),
      );
    });

    test('rejects malformed UTF-8', () {
      final fixture = _SourceFixture.createBytes(<int>[
        ...utf8.encode('keybay:\n  application_id: dev.example\n'),
        0xff,
      ]);
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver().resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.invalidDeclaration)),
      );
    });
  });

  group('activation and unsupported launch modes', () {
    test('resolves only from the package-config activation root', () {
      final activation = _ActivationFixture.create(
        applicationId: 'dev.activated',
      );
      addTearDown(activation.dispose);

      final identity = activation.resolver().resolve();

      expect(identity.stableValue, 'dev.activated');
      expect(identity.source, ApplicationIdentitySource.activatedPubspec);
      expect(identity.assurance, ApplicationIdentityAssurance.namespaceOnly);
    });

    test('rejects a runner outside the activation bin directory', () {
      final activation = _ActivationFixture.create(
        applicationId: 'dev.activated',
      );
      final outsideRunner = File(
        '${activation.root.path}${Platform.pathSeparator}runner.dill',
      )..writeAsBytesSync(const <int>[]);
      addTearDown(activation.dispose);

      expect(
        DartApplicationIdentityResolver(
          DartRuntimeIdentityInputs(
            script: outsideRunner.uri,
            packageConfig: activation.packageConfig.uri,
            resolvedExecutable: Uri.file(Platform.resolvedExecutable),
            embeddedApplicationId: '',
          ),
        ).resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
      );
    });

    test('package:test-style runner fails closed', () {
      final packageRoot = Directory.systemTemp.createTempSync(
        'keybay-test-package-',
      );
      final dartTool = Directory(
        '${packageRoot.path}${Platform.pathSeparator}.dart_tool',
      )..createSync();
      final packageConfig = File(
        '${dartTool.path}${Platform.pathSeparator}package_config.json',
      )..writeAsStringSync('{"configVersion":2,"packages":[]}');
      File(
        '${packageRoot.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('keybay:\n  application_id: dev.decoy\n');
      final runnerRoot = Directory.systemTemp.createTempSync(
        'keybay-test-runner-',
      );
      final runner = File(
        '${runnerRoot.path}${Platform.pathSeparator}test.dart.dill',
      )..writeAsBytesSync(const <int>[]);
      addTearDown(() => packageRoot.deleteSync(recursive: true));
      addTearDown(() => runnerRoot.deleteSync(recursive: true));

      expect(
        DartApplicationIdentityResolver(
          DartRuntimeIdentityInputs(
            script: runner.uri,
            packageConfig: packageConfig.uri,
            resolvedExecutable: Uri.file(Platform.resolvedExecutable),
            embeddedApplicationId: '',
          ),
        ).resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
      );
    });

    test('an embedded ID cannot authorize an unsupported runner', () {
      final runnerRoot = Directory.systemTemp.createTempSync(
        'keybay-unsupported-runner-',
      );
      final runner = File(
        '${runnerRoot.path}${Platform.pathSeparator}test.dart.dill',
      )..writeAsBytesSync(const <int>[]);
      addTearDown(() => runnerRoot.deleteSync(recursive: true));

      expect(
        DartApplicationIdentityResolver(
          DartRuntimeIdentityInputs(
            script: runner.uri,
            packageConfig: null,
            resolvedExecutable: Uri.file(Platform.resolvedExecutable),
            embeddedApplicationId: 'dev.must-not-authorize-test',
          ),
        ).resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
      );
    });
  });

  group('dart install identity', () {
    for (final source in <String>['local', 'hosted', 'git']) {
      test('resolves the retained pubspec from a $source app bundle', () {
        final fixture = _DartInstallFixture.create(source: source);
        addTearDown(fixture.dispose);

        final identity = fixture.resolver().resolve();

        expect(identity.stableValue, 'dev.installed');
        expect(identity.source, ApplicationIdentitySource.dartInstallPubspec);
        expect(identity.assurance, ApplicationIdentityAssurance.namespaceOnly);
      });
    }

    test('requires embedded and installed declarations to agree', () {
      final fixture = _DartInstallFixture.create(source: 'local');
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver(embeddedApplicationId: 'dev.other').resolve,
        throwsA(
          _failure(ApplicationIdentityFailureCode.conflictingDeclarations),
        ),
      );
      expect(
        fixture
            .resolver(embeddedApplicationId: 'dev.installed')
            .resolve()
            .stableValue,
        'dev.installed',
      );
    });

    test('rejects an incomplete recognized app bundle', () {
      final fixture = _DartInstallFixture.create(
        source: 'local',
        includeLock: false,
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver(embeddedApplicationId: 'dev.installed').resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.metadataUnreadable)),
      );
    });

    test('does not treat a lookalike executable tree as dart install', () {
      final fixture = _DartInstallFixture.create(
        source: 'local',
        appBundlesDirectoryName: 'other-bundles',
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver().resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
      );
    });

    test('requires the dart install root shape', () {
      final fixture = _DartInstallFixture.create(
        source: 'local',
        installDirectoryName: 'other-install',
      );
      addTearDown(fixture.dispose);

      expect(
        fixture.resolver().resolve,
        throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
      );
    });
  });

  group('build-embedded identity', () {
    test('separate native AOT images require an embedded declaration', () {
      final root = Directory.systemTemp.createTempSync('keybay-aot-module-');
      addTearDown(() => root.deleteSync(recursive: true));
      final runtime = File('${root.path}/runtime')..writeAsBytesSync([]);
      final module = File('${root.path}/module');
      DartApplicationIdentityResolver resolver(
        String embedded, {
        Uri? config,
      }) => DartApplicationIdentityResolver(
        DartRuntimeIdentityInputs(
          script: module.uri,
          packageConfig: config,
          resolvedExecutable: runtime.uri,
          embeddedApplicationId: embedded,
        ),
      );
      for (final header in [
        [0x7f, 0x45, 0x4c, 0x46],
        [0xcf, 0xfa, 0xed, 0xfe],
      ]) {
        module.writeAsBytesSync(header);
        expect(
          resolver('dev.compiled').resolve().source,
          ApplicationIdentitySource.buildEmbedded,
        );
        expect(
          resolver('').resolve,
          throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
        );
        expect(
          resolver(
            'dev.compiled',
            config: root.uri.resolve('package_config.json'),
          ).resolve().source,
          ApplicationIdentitySource.buildEmbedded,
        );
      }
      for (final bytes in [
        <int>[],
        [0x7f, 0x45],
        utf8.encode('void main() {}'),
      ]) {
        module.writeAsBytesSync(bytes);
        expect(
          resolver('dev.compiled').resolve,
          throwsA(_failure(ApplicationIdentityFailureCode.unavailable)),
        );
      }
    });

    test('opens a controlled AOT-style executable declaration', () {
      final executableRoot = Directory.systemTemp.createTempSync('keybay-aot-');
      final executable = File(
        '${executableRoot.path}${Platform.pathSeparator}example',
      )..writeAsBytesSync(const <int>[]);
      addTearDown(() => executableRoot.deleteSync(recursive: true));

      final identity = DartApplicationIdentityResolver(
        DartRuntimeIdentityInputs(
          script: executable.uri,
          packageConfig: null,
          resolvedExecutable: executable.uri,
          embeddedApplicationId: 'dev.compiled',
        ),
      ).resolve();

      expect(identity.stableValue, 'dev.compiled');
      expect(identity.source, ApplicationIdentitySource.buildEmbedded);
      expect(identity.assurance, ApplicationIdentityAssurance.namespaceOnly);
    });

    test('classifies AOT from executable identity, not its filename', () {
      final executableRoot = Directory.systemTemp.createTempSync(
        'keybay-aot-dart-suffix-',
      );
      final executable = File(
        '${executableRoot.path}${Platform.pathSeparator}example.dart',
      )..writeAsBytesSync(const <int>[]);
      addTearDown(() => executableRoot.deleteSync(recursive: true));

      final identity = DartApplicationIdentityResolver(
        DartRuntimeIdentityInputs(
          script: executable.uri,
          packageConfig: null,
          resolvedExecutable: executable.uri,
          embeddedApplicationId: 'dev.compiled',
        ),
      ).resolve();

      expect(identity.stableValue, 'dev.compiled');
      expect(identity.source, ApplicationIdentitySource.buildEmbedded);
    });

    test('fails when compiled metadata is absent or invalid', () {
      final executableRoot = Directory.systemTemp.createTempSync(
        'keybay-aot-invalid-',
      );
      final executable = File(
        '${executableRoot.path}${Platform.pathSeparator}example',
      )..writeAsBytesSync(const <int>[]);
      addTearDown(() => executableRoot.deleteSync(recursive: true));

      for (final embedded in <String>['', '../other']) {
        expect(
          DartApplicationIdentityResolver(
            DartRuntimeIdentityInputs(
              script: executable.uri,
              packageConfig: null,
              resolvedExecutable: executable.uri,
              embeddedApplicationId: embedded,
            ),
          ).resolve,
          throwsA(
            _failure(
              embedded.isEmpty
                  ? ApplicationIdentityFailureCode.unavailable
                  : ApplicationIdentityFailureCode.invalidDeclaration,
            ),
          ),
        );
      }
    });
  });

  test('identity and failures redact values and paths', () {
    const marker = 'dev.secret-looking-marker';
    final fixture = _SourceFixture.create(
      pubspec: 'keybay:\n  application_id: $marker\n',
    );
    addTearDown(fixture.dispose);

    final identity = fixture.resolver().resolve();
    expect(identity.toString(), isNot(contains(marker)));

    final failure = ApplicationIdentityFailure(
      ApplicationIdentityFailureCode.metadataUnreadable,
    );
    expect(failure.toString(), isNot(contains(marker)));
    expect(failure.toString(), isNot(contains(fixture.root.path)));
  });
}

Matcher _failure(ApplicationIdentityFailureCode code) =>
    isA<ApplicationIdentityFailure>().having(
      (failure) => failure.code,
      'code',
      code,
    );

final class _SourceFixture {
  _SourceFixture._({required this.root, required this.script});

  factory _SourceFixture.create({required String pubspec}) =>
      _SourceFixture.createBytes(utf8.encode(pubspec));

  factory _SourceFixture.createBytes(List<int> pubspecBytes) {
    final root = Directory.systemTemp.createTempSync('keybay-source-app-');
    final bin = Directory('${root.path}${Platform.pathSeparator}bin')
      ..createSync();
    final script = File('${bin.path}${Platform.pathSeparator}main.dart')
      ..writeAsStringSync('void main() {}');
    File(
      '${root.path}${Platform.pathSeparator}pubspec.yaml',
    ).writeAsBytesSync(pubspecBytes);
    return _SourceFixture._(root: root, script: script);
  }

  final Directory root;
  final File script;

  DartApplicationIdentityResolver resolver({
    String embeddedApplicationId = '',
  }) => DartApplicationIdentityResolver(
    DartRuntimeIdentityInputs(
      script: script.uri,
      packageConfig: null,
      resolvedExecutable: Uri.file(Platform.resolvedExecutable),
      embeddedApplicationId: embeddedApplicationId,
    ),
  );

  void dispose() => root.deleteSync(recursive: true);
}

final class _ActivationFixture {
  _ActivationFixture._({
    required this.root,
    required this.runner,
    required this.packageConfig,
  });

  factory _ActivationFixture.create({required String applicationId}) {
    final root = Directory.systemTemp.createTempSync('keybay-activation-');
    final dartTool = Directory(
      '${root.path}${Platform.pathSeparator}.dart_tool',
    )..createSync();
    final packageConfig = File(
      '${dartTool.path}${Platform.pathSeparator}package_config.json',
    )..writeAsStringSync('{"configVersion":2,"packages":[]}');
    final bin = Directory(
      '${dartTool.path}${Platform.pathSeparator}pub'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}example',
    )..createSync(recursive: true);
    final runner = File(
      '${bin.path}${Platform.pathSeparator}example.dart.snapshot',
    )..writeAsBytesSync(const <int>[]);
    File('${root.path}${Platform.pathSeparator}pubspec.yaml').writeAsStringSync(
      'name: example\nkeybay:\n  application_id: $applicationId\n',
    );
    return _ActivationFixture._(
      root: root,
      runner: runner,
      packageConfig: packageConfig,
    );
  }

  final Directory root;
  final File runner;
  final File packageConfig;

  DartApplicationIdentityResolver resolver() => DartApplicationIdentityResolver(
    DartRuntimeIdentityInputs(
      script: runner.uri,
      packageConfig: packageConfig.uri,
      resolvedExecutable: Uri.file(Platform.resolvedExecutable),
      embeddedApplicationId: '',
    ),
  );

  void dispose() => root.deleteSync(recursive: true);
}

final class _DartInstallFixture {
  _DartInstallFixture._({required this.root, required this.executable});

  factory _DartInstallFixture.create({
    required String source,
    bool includeLock = true,
    String installDirectoryName = 'install',
    String appBundlesDirectoryName = 'app-bundles',
  }) {
    final root = Directory.systemTemp.createTempSync('keybay-dart-install-');
    final packageRoot = Directory(
      '${root.path}${Platform.pathSeparator}$installDirectoryName'
      '${Platform.pathSeparator}$appBundlesDirectoryName'
      '${Platform.pathSeparator}example',
    );
    final appBundle = source == 'local'
        ? Directory('${packageRoot.path}${Platform.pathSeparator}local')
        : Directory(
            '${packageRoot.path}${Platform.pathSeparator}$source'
            '${Platform.pathSeparator}qualifier',
          );
    final bin = Directory(
      '${appBundle.path}${Platform.pathSeparator}bundle'
      '${Platform.pathSeparator}bin',
    )..createSync(recursive: true);
    final executable = File(
      '${bin.path}${Platform.pathSeparator}example'
      '${Platform.isWindows ? '.exe' : ''}',
    )..writeAsBytesSync(const <int>[]);
    File(
      '${appBundle.path}${Platform.pathSeparator}pubspec.yaml',
    ).writeAsStringSync(
      'name: example\nkeybay:\n  application_id: dev.installed\n',
    );
    if (includeLock) {
      File(
        '${appBundle.path}${Platform.pathSeparator}pubspec.lock',
      ).writeAsStringSync('packages: {}\n');
    }
    return _DartInstallFixture._(root: root, executable: executable);
  }

  final Directory root;
  final File executable;

  DartApplicationIdentityResolver resolver({
    String embeddedApplicationId = '',
  }) => DartApplicationIdentityResolver(
    DartRuntimeIdentityInputs(
      script: executable.uri,
      packageConfig: null,
      resolvedExecutable: executable.uri,
      embeddedApplicationId: embeddedApplicationId,
    ),
  );

  void dispose() => root.deleteSync(recursive: true);
}
