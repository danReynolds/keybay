import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay_cli/src/secret_input.dart';
import 'package:keybay_cli/src/lifetime.dart';
import 'package:test/test.dart';

void main() {
  group('stdin secret decoding', () {
    test('strips exactly one LF or CRLF and keeps a lone CR', () {
      expect(utf8.decode(decodeSecretBytes(utf8.encode('value\n'))), 'value');
      expect(utf8.decode(decodeSecretBytes(utf8.encode('value\r\n'))), 'value');
      expect(
        utf8.decode(decodeSecretBytes(utf8.encode('value\n\n'))),
        'value\n',
      );
      expect(utf8.decode(decodeSecretBytes(utf8.encode('value\r'))), 'value\r');
    });

    test('rejects empty input so a failed producer cannot store ""', () {
      // `op read … | keybay set --stdin key` with a silently failing producer
      // exits 0 without pipefail; accepting the empty read would replace a
      // real credential with the empty string.
      for (final bytes in <List<int>>[
        const <int>[],
        utf8.encode('\n'),
        utf8.encode('\r\n'),
      ]) {
        expect(
          () => decodeSecretBytes(bytes),
          throwsA(
            isA<SecretInputException>().having(
              (error) => error.message,
              'message',
              contains('empty'),
            ),
          ),
        );
      }
    });

    test('rejects malformed UTF-8 and NUL without echoing input', () {
      const sentinel = 'never-echo-this-input';
      for (final entry in <(List<int>, String)>[
        (<int>[0xff, 0xfe], 'provide a UTF-8 text value'),
        (utf8.encode('$sentinel\u0000tail'), 'provide text without NUL'),
      ]) {
        late final SecretInputException error;
        try {
          decodeSecretBytes(entry.$1);
          fail('expected input failure');
        } on SecretInputException catch (caught) {
          error = caught;
        }
        expect(error.toString(), isNot(contains(sentinel)));
        expect(error.message, contains(entry.$2));
      }
    });

    test('rejects input beyond the public record limit before decoding', () {
      final oversized = Uint8List(maxSecretInputBytes + 1);
      expect(
        () => decodeSecretBytes(oversized),
        throwsA(
          isA<SecretInputException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('1 MiB record limit'),
              contains('credential rather than a blob'),
            ),
          ),
        ),
      );
    });
  });

  test('public maximum value accepts exactly one producer ending', () {
    final bytes = Uint8List(maxSecretInputBytes + 2)
      ..fillRange(0, maxSecretInputBytes, 0x61);
    bytes[maxSecretInputBytes] = 0x0d;
    bytes[maxSecretInputBytes + 1] = 0x0a;
    final result = decodeSecretBytes(bytes);
    expect(result.length, maxSecretInputBytes);
    result.fillRange(0, result.length, 0);
  });

  test(
    'interrupting partial hidden input restores echo and cancels input',
    () async {
      final lifetime = CommandLifetime();
      final terminal = _FakeTerminal(hasTerminal: true, echoMode: true);
      var cancelled = false;
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final reader = SecretInputReader(
        input: stream.stream,
        terminal: terminal,
        stderr: StringBuffer(),
        lifetime: lifetime,
      );
      final reading = reader.read(key: 'acme/key', fromStdin: false);
      stream.add(utf8.encode('partial-sentinel'));
      await Future<void>.delayed(Duration.zero);
      lifetime.cancel();
      await expectLater(reading, throwsA(isA<CommandInterrupted>()));
      expect(terminal.echoMode, isTrue);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );

  group('reader', () {
    Future<Uint8List> hidden(List<List<int>> chunks) => SecretInputReader(
      input: Stream.fromIterable(chunks),
      terminal: _FakeTerminal(hasTerminal: true, echoMode: true),
      stderr: StringBuffer(),
      lifetime: CommandLifetime(),
    ).read(key: 'probe/key', fromStdin: false);

    test(
      'fragmented bracketed paste preserves all bytes and trailing CRLF',
      () async {
        const text = 'probe\r\n🔑\x03\t\x1b[31m\r\n';
        final wire = utf8.encode('\x1b[200~$text\x1b[201~\r');
        for (var split = 0; split <= wire.length; split++) {
          final value = await hidden([
            wire.sublist(0, split),
            wire.sublist(split),
          ]);
          expect(value, utf8.encode(text), reason: 'wire split $split');
        }
        expect(await hidden(wire.map((b) => [b]).toList()), utf8.encode(text));
      },
    );

    test(
      'hidden editing erases a UTF-8 code point and clears the draft',
      () async {
        expect(await hidden([utf8.encode('xé\x7f\r')]), utf8.encode('x'));
        expect(
          await hidden([utf8.encode('discard\x15kept\r')]),
          utf8.encode('kept'),
        );
        expect(await hidden([utf8.encode('kept\x04')]), utf8.encode('kept'));
        await expectLater(
          hidden([
            [3],
          ]),
          throwsA(isA<CommandInterrupted>()),
        );
      },
    );

    test('incomplete paste is never accepted at EOF', () async {
      await expectLater(
        hidden([utf8.encode('\x1b[200~not-submitted\n')]),
        throwsA(isA<SecretInputException>()),
      );
    });

    test('--stdin reads to EOF without requiring a terminal', () async {
      final terminal = _FakeTerminal(hasTerminal: false, echoMode: true);
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: Stream<List<int>>.fromIterable(<List<int>>[
          utf8.encode('multi'),
          utf8.encode('-chunk\n'),
        ]),
        terminal: terminal,
        stderr: StringBuffer(),
      );

      expect(
        utf8.decode(await reader.read(key: 'acme/key', fromStdin: true)),
        'multi-chunk',
      );
      expect(terminal.setCalls, isEmpty);
    });

    test('--stdin bounds the stream at the public record limit', () async {
      const sentinel = 'tail-must-not-be-consumed-or-echoed';
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: Stream<List<int>>.fromIterable(<List<int>>[
          Uint8List(maxSecretInputBytes + 2),
          utf8.encode(sentinel),
        ]),
        terminal: _FakeTerminal(hasTerminal: false, echoMode: true),
        stderr: StringBuffer(),
      );

      await expectLater(
        reader.read(key: 'acme/key', fromStdin: true),
        throwsA(
          isA<SecretInputException>().having(
            (error) => error.message,
            'message',
            contains('1 MiB record limit'),
          ),
        ),
      );
    });

    test('--stdin refuses a terminal so the secret is never echoed', () async {
      // The mirror of the interactive branch's TTY requirement: typing into
      // `--stdin` at a terminal would echo the secret into scrollback.
      final terminal = _FakeTerminal(hasTerminal: true, echoMode: true);
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: const Stream<List<int>>.empty(),
        terminal: terminal,
        stderr: StringBuffer(),
      );

      await expectLater(
        reader.read(key: 'acme/key', fromStdin: true),
        throwsA(
          isA<SecretInputException>().having(
            (error) => error.message,
            'guidance',
            contains('drop --stdin'),
          ),
        ),
      );
      // Refused before any read or echo manipulation.
      expect(terminal.setCalls, isEmpty);
    });

    test('interactive mode refuses redirected stdin', () async {
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: const Stream<List<int>>.empty(),
        terminal: _FakeTerminal(hasTerminal: false, echoMode: true),
        stderr: StringBuffer(),
      );

      await expectLater(
        reader.read(key: 'acme/key', fromStdin: false),
        throwsA(
          isA<SecretInputException>().having(
            (error) => error.message,
            'guidance',
            contains('--stdin'),
          ),
        ),
      );
    });

    test(
      'interactive mode refuses a background TTY before changing echo',
      () async {
        final terminal = _FakeTerminal(
          hasTerminal: true,
          isForeground: false,
          echoMode: true,
        );
        final reader = SecretInputReader(
          lifetime: CommandLifetime(),
          input: const Stream<List<int>>.empty(),
          terminal: terminal,
          stderr: StringBuffer(),
        );

        await expectLater(
          reader.read(key: 'acme/key', fromStdin: false),
          throwsA(
            isA<SecretInputException>().having(
              (error) => error.message,
              'guidance',
              contains('foreground'),
            ),
          ),
        );
        expect(terminal.setCalls, isEmpty);
        expect(terminal.echoMode, isTrue);
      },
    );

    test(
      'interactive mode hides input and restores the exact prior mode',
      () async {
        const sentinel = 'hidden-value';
        for (final previousMode in <bool>[true, false]) {
          final terminal = _FakeTerminal(
            hasTerminal: true,
            echoMode: previousMode,
          );
          final stderr = StringBuffer();
          final reader = SecretInputReader(
            lifetime: CommandLifetime(),
            input: Stream<List<int>>.value(utf8.encode('$sentinel\nignored')),
            terminal: terminal,
            stderr: stderr,
          );

          expect(
            utf8.decode(await reader.read(key: 'acme/key', fromStdin: false)),
            sentinel,
          );
          expect(terminal.echoMode, previousMode);
          expect(terminal.setCalls.first, isFalse);
          expect(terminal.setCalls.last, previousMode);
          expect(stderr.toString(), contains('Value for acme/key'));
          expect(stderr.toString(), isNot(contains(sentinel)));
        }
      },
    );

    test('interactive mode restores echo when decoding fails', () async {
      final terminal = _FakeTerminal(hasTerminal: true, echoMode: true);
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: Stream<List<int>>.value(<int>[0xff, 0x0a]),
        terminal: terminal,
        stderr: StringBuffer(),
      );

      await expectLater(
        reader.read(key: 'acme/key', fromStdin: false),
        throwsA(isA<SecretInputException>()),
      );
      expect(terminal.echoMode, isTrue);
      expect(terminal.setCalls, <bool>[false, true]);
    });

    test(
      'interactive mode cancels input when echo restoration fails',
      () async {
        var inputCancelled = false;
        final input = StreamController<List<int>>(
          onCancel: () => inputCancelled = true,
        );
        final terminal = _FakeTerminal(
          hasTerminal: true,
          echoMode: true,
          failOnSetCall: 2,
        );
        final reader = SecretInputReader(
          lifetime: CommandLifetime(),
          input: input.stream,
          terminal: terminal,
          stderr: StringBuffer(),
        );

        final read = reader.read(key: 'acme/key', fromStdin: false);
        input.add(utf8.encode('value\n'));

        await expectLater(read, throwsA(isA<StateError>()));
        expect(inputCancelled, isTrue);
        expect(terminal.setCalls, <bool>[false, true]);
        await input.close();
      },
    );

    test('interactive mode accepts a chunked final line at EOF', () async {
      final terminal = _FakeTerminal(hasTerminal: true, echoMode: true);
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: Stream<List<int>>.fromIterable(<List<int>>[
          utf8.encode('chunked-'),
          utf8.encode('value'),
        ]),
        terminal: terminal,
        stderr: StringBuffer(),
      );

      expect(
        utf8.decode(await reader.read(key: 'acme/key', fromStdin: false)),
        'chunked-value',
      );
      expect(terminal.echoMode, isTrue);
      expect(terminal.setCalls, <bool>[false, true]);
    });

    test('interactive mode bounds input before a newline arrives', () async {
      final terminal = _FakeTerminal(hasTerminal: true, echoMode: true);
      final reader = SecretInputReader(
        lifetime: CommandLifetime(),
        input: Stream<List<int>>.value(Uint8List(maxSecretInputBytes + 2)),
        terminal: terminal,
        stderr: StringBuffer(),
      );

      await expectLater(
        reader.read(key: 'acme/key', fromStdin: false),
        throwsA(
          isA<SecretInputException>().having(
            (error) => error.message,
            'message',
            contains('1 MiB record limit'),
          ),
        ),
      );
      expect(terminal.echoMode, isTrue);
      expect(terminal.setCalls, <bool>[false, true]);
    });
  });

  group('passphrase byte contract', () {
    test('excludes one line ending without trimming or normalization', () {
      expect(
        utf8.decode(decodePassphraseBytes(utf8.encode('  pass phrase  \n'))),
        '  pass phrase  ',
      );
      expect(
        decodePassphraseBytes(utf8.encode('\u00e9\n')),
        utf8.encode('\u00e9'),
      );
    });

    test('requires valid UTF-8 containing 1 to 1024 bytes', () {
      for (final value in <List<int>>[
        const <int>[],
        const <int>[0x0a],
        const <int>[0xff, 0x0a],
        Uint8List(maxPassphraseInputBytes + 2),
      ]) {
        expect(
          () => decodePassphraseBytes(value),
          throwsA(isA<SecretInputException>()),
        );
      }
    });
  });
}

final class _FakeTerminal implements TerminalControl {
  _FakeTerminal({
    required this.hasTerminal,
    this.isForeground = true,
    required bool echoMode,
    this.failOnSetCall,
  }) : _echoMode = echoMode;

  @override
  final bool hasTerminal;
  @override
  final bool isForeground;
  bool _echoMode;
  final int? failOnSetCall;
  final List<bool> setCalls = <bool>[];

  @override
  bool get echoMode => _echoMode;

  @override
  set echoMode(bool value) {
    setCalls.add(value);
    if (setCalls.length == failOnSetCall) {
      throw StateError('terminal disappeared');
    }
    _echoMode = value;
  }
}
