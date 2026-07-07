@Tags(['integration'])
@TestOn('linux')
library;

import 'dart:io';

import 'package:secret_store/secret_store.dart';
import 'package:test/test.dart';

/// Exercises the REAL `systemd-creds` wrap/unwrap round-trip. Opt-in and
/// Linux-only. Uses the `host` binding so it needs no TPM (CI has none) — that
/// still proves the subprocess plumbing (base64 transport, blob persistence,
/// exit-code handling); the `tpm2`/`host+tpm2` bindings are the same code path
/// with a different `--with-key` flag.
///
/// CI runs it directly (no D-Bus needed, unlike the Secret Service tier).
void main() {
  final envEnabled = Platform.environment['SECRET_STORE_INTEGRATION'] == '1';
  final skip = envEnabled
      ? false
      : 'set SECRET_STORE_INTEGRATION=1 (Linux, systemd-creds present)';

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ss_tpm_it_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  TpmKeySource src() => TpmKeySource(
        path: '${tmp.path}/store.cred',
        binding: TpmKeyBinding.host, // no TPM in CI
      );

  test('systemd-creds wraps the key on disk and unwraps it (host binding)',
      () async {
    final ks = src();
    expect(await ks.read(), isNull); // fresh: no blob yet

    final key = await ks.create();
    expect(key, hasLength(storeKeyLength));

    // What's on disk is the encrypted credential, not the key: it's larger
    // than 32 bytes (systemd-creds framing) and a fresh source unwraps it back
    // to the identical key.
    final blob = File('${tmp.path}/store.cred').readAsBytesSync();
    expect(blob.length, greaterThan(storeKeyLength));
    expect(await src().read(), key);
  }, skip: skip);

  test('delete removes the blob; read is null again', () async {
    final ks = src();
    await ks.create();
    await ks.delete();
    expect(await ks.read(), isNull);
  }, skip: skip);

  test('describe reports systemd-creds reachable', () async {
    final s = await src().describe();
    expect(s.available, isTrue); // host binding needs no TPM
    expect(s.detail, contains('systemd-creds=ok'));
  }, skip: skip);
}
