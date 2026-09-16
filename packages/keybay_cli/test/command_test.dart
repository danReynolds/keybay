import 'package:keybay_cli/src/command.dart';
import 'package:test/test.dart';

void main() {
  group('command parser', () {
    test('open takes no flags or arguments', () {
      expect(parseCommand(['open']), isA<OpenCommand>());
      expect(
        () => parseCommand(['open', '--help']),
        throwsA(isA<CliUsageException>()),
      );
      expect(
        () => parseCommand(['open', 'store']),
        throwsA(isA<CliUsageException>()),
      );
    });
    test('parses the two global flags', () {
      expect(parseCommand(<String>['--help']), isA<HelpCommand>());
      expect(parseCommand(<String>['--version']), isA<VersionCommand>());
    });

    test('parses run with the default manifest', () {
      final command = parseCommand(<String>[
        'run',
        '--',
        'npm',
        'start',
        '--watch',
      ]);

      expect(command, isA<RunCommand>());
      final run = command as RunCommand;
      expect(run.manifestPath, './.env');
      expect(run.executable, 'npm');
      expect(run.arguments, <String>['start', '--watch']);
    });

    test('parses run with exactly one explicit manifest', () {
      final command =
          parseCommand(<String>[
                'run',
                '-f',
                '.env.production',
                '--',
                'go',
                'run',
                '.',
              ])
              as RunCommand;

      expect(command.manifestPath, '.env.production');
      expect(command.executable, 'go');
      expect(command.arguments, <String>['run', '.']);
    });

    test('requires the run delimiter and child command', () {
      for (final arguments in <List<String>>[
        <String>['run'],
        <String>['run', 'npm', 'start'],
        <String>['run', '--'],
        <String>['run', '-f'],
        <String>['run', '-f', 'file', 'npm'],
        <String>['run', '-f', 'one', '-f', 'two', '--', 'true'],
      ]) {
        expect(
          () => parseCommand(arguments),
          throwsA(isA<CliUsageException>()),
        );
      }
    });

    test('parses set only with an optional leading --stdin', () {
      final interactive =
          parseCommand(<String>['set', 'acme/project-key']) as SetCommand;
      expect(interactive.key, 'acme/project-key');
      expect(interactive.readFromStdin, isFalse);

      final piped =
          parseCommand(<String>['set', '--stdin', 'acme/project-key'])
              as SetCommand;
      expect(piped.key, 'acme/project-key');
      expect(piped.readFromStdin, isTrue);

      expect(
        () => parseCommand(<String>['set', 'acme/project-key', '--stdin']),
        throwsA(isA<CliUsageException>()),
      );
    });

    test('parses get, rm, and list', () {
      final get =
          parseCommand(<String>['get', 'acme/project-key']) as GetCommand;
      expect(get.key, 'acme/project-key');
      final remove =
          parseCommand(<String>['rm', 'acme/project-key']) as RemoveCommand;
      expect(remove.key, 'acme/project-key');
      expect(parseCommand(<String>['list']), isA<ListCommand>());
    });

    test('accepts simple and namespaced keys for every single-key command', () {
      for (final key in ['x', 'x/y']) {
        expect((parseCommand(['set', key]) as SetCommand).key, key);
        expect((parseCommand(['set', '--stdin', key]) as SetCommand).key, key);
        expect((parseCommand(['get', key]) as GetCommand).key, key);
        expect((parseCommand(['rm', key]) as RemoveCommand).key, key);
      }
    });

    test('rejects extra arguments and unknown commands', () {
      for (final arguments in <List<String>>[
        <String>[],
        <String>['list', 'acme'],
        <String>['doctor'],
        <String>['doctor', '--verbose'],
        <String>['get'],
        <String>['get', 'acme/key', 'extra'],
        <String>['--quiet', 'list'],
      ]) {
        expect(
          () => parseCommand(arguments),
          throwsA(isA<CliUsageException>()),
        );
      }
    });

    test('usage errors do not echo an invalid argument', () {
      const sentinel = 'do not echo this secret';
      late final CliUsageException error;
      try {
        parseCommand(<String>['set', sentinel]);
        fail('expected usage error');
      } on CliUsageException catch (caught) {
        error = caught;
      }
      expect(error.toString(), isNot(contains(sentinel)));
    });
  });
}
