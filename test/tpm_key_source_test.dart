@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:secret_store/secret_store.dart';
import 'package:test/test.dart';

/// Scripted [ProcessRunner]: records calls and returns canned outcomes, so the
/// `systemd-creds` command construction, base64 key transport, error mapping,
/// and output scrubbing are tested without a real TPM or systemd. The real
/// round-trip is covered by a Linux/Docker integration test.
class ScriptedRunner implements ProcessRunner {
  ScriptedRunner(this._respond);
  final ProcessRunResult Function(List<String> args, String? stdin) _respond;
  final List<List<String>> calls = [];
  final List<String?> stdins = [];
  final List<ProcessRunResult> results = [];

  @override
  Future<ProcessRunResult> run(String executable, List<String> args,
      {String? stdin, required Duration timeout}) async {
    calls.add(args);
    stdins.add(stdin);
    final r = _respond(args, stdin);
    results.add(r);
    return r;
  }
}

ProcessRunResult _ok(List<int> stdout) => ProcessRunResult(
    exitCode: 0,
    stdout: Uint8List.fromList(stdout),
    stderr: Uint8List(0),
    timedOut: false,
    launchFailed: false);
ProcessRunResult _exit(int code) => ProcessRunResult(
    exitCode: code,
    stdout: Uint8List(0),
    stderr: Uint8List(0),
    timedOut: false,
    launchFailed: false);
ProcessRunResult _launchFailed() => ProcessRunResult(
    exitCode: -1,
    stdout: Uint8List(0),
    stderr: Uint8List(0),
    timedOut: false,
    launchFailed: true);

/// A fake systemd-creds that models encrypt/decrypt as identity over the
/// stdin: the "blob" it emits is exactly the base64 it was handed, and decrypt
/// hands it back — enough to exercise the full wrap/unwrap plumbing.
ScriptedRunner identityCreds({bool tpm = true}) =>
    ScriptedRunner((args, stdin) {
      if (args.first == 'has-tpm2') return _exit(tpm ? 0 : 27);
      // encrypt and decrypt both echo stdin as stdout (identity transform).
      return _ok(utf8.encode(stdin ?? ''));
    });

void main() {
  late Directory tmp;
  late String blobPath;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ss_tpm_');
    blobPath = '${tmp.path}/store.cred';
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  TpmKeySource source(ScriptedRunner r,
          {TpmKeyBinding binding = TpmKeyBinding.hostAndTpm2}) =>
      TpmKeySource(path: blobPath, binding: binding, runner: r);

  test('create wraps a 32-byte key and persists the blob 0600', () async {
    final r = identityCreds();
    final ks = source(r);
    final key = await ks.create();

    expect(key, hasLength(storeKeyLength));
    // encrypt was invoked with the right verb/name/binding and the key as
    // base64 on stdin (never raw bytes on argv).
    expect(r.calls.first,
        ['encrypt', '--name=secret_store', '--with-key=host+tpm2', '-', '-']);
    expect(r.stdins.first, base64.encode(key));
    // the blob (identity fake: == the base64 key) landed on disk, 0600.
    expect(File(blobPath).existsSync(), isTrue);
    expect(File(blobPath).statSync().mode & 0x1FF, 0x180);
  });

  test('round-trips: read after create returns the same key', () async {
    final r = identityCreds();
    final ks = source(r);
    final created = await ks.create();
    final read = await ks.read();
    expect(read, created);
    expect(r.calls.map((c) => c.first), ['encrypt', 'decrypt']);
    expect(r.calls.last,
        ['decrypt', '--name=secret_store', '--with-key=host+tpm2', '-', '-']);
  });

  test('read on a missing blob is null', () async {
    expect(await source(identityCreds()).read(), isNull);
  });

  test('binding selects the --with-key value', () async {
    for (final (b, v) in [
      (TpmKeyBinding.tpm2, 'tpm2'),
      (TpmKeyBinding.host, 'host'),
    ]) {
      final r = identityCreds();
      await source(r, binding: b).create();
      expect(r.calls.first, contains('--with-key=$v'));
    }
  });

  test('missing systemd-creds -> KeystoreUnreachable', () async {
    final ks = source(ScriptedRunner((a, s) => _launchFailed()));
    await expectLater(ks.create(), throwsA(isA<KeystoreUnreachable>()));
  });

  test('nonzero encrypt exit -> KeystoreOperationFailed', () async {
    final ks = source(ScriptedRunner((a, s) => _exit(1)));
    await expectLater(ks.create(), throwsA(isA<KeystoreOperationFailed>()));
  });

  test('a non-base64 unwrapped value -> typed KeystoreOperationFailed',
      () async {
    // Blob exists, but decrypt yields garbage (not the base64 we wrapped).
    File(blobPath).writeAsStringSync('blob');
    final ks = source(ScriptedRunner((a, s) {
      if (a.first == 'has-tpm2') return _exit(0);
      return _ok(utf8.encode('not valid base64 !!'));
    }));
    await expectLater(ks.read(), throwsA(isA<KeystoreOperationFailed>()));
  });

  test('output buffers are scrubbed (the key transits stdout on decrypt)',
      () async {
    final r = identityCreds();
    final ks = source(r);
    await ks.create();
    await ks.read();
    for (final res in r.results) {
      expect(res.stdout, everyElement(0),
          reason: 'stdout must be zeroed after use');
    }
  });

  group('describe', () {
    test('reports binding, TPM presence, and blob presence', () async {
      final ks = source(identityCreds(tpm: true));
      var s = await ks.describe();
      expect(s.name, 'tpm');
      expect(s.present, isFalse);
      expect(s.available, isTrue);
      expect(s.detail, contains('binding=host+tpm2'));
      expect(s.detail, contains('tpm2=present'));

      await ks.create();
      s = await ks.describe();
      expect(s.present, isTrue);
    });

    test('a TPM-requiring binding is unavailable without a TPM', () async {
      final s = await source(identityCreds(tpm: false)).describe();
      expect(s.available, isFalse, reason: 'host+tpm2 needs a TPM');
      expect(s.detail, contains('tpm2=absent'));
    });

    test('the host binding is available without a TPM', () async {
      final s =
          await source(identityCreds(tpm: false), binding: TpmKeyBinding.host)
              .describe();
      expect(s.available, isTrue, reason: 'host binding needs no TPM');
    });
  });
}
