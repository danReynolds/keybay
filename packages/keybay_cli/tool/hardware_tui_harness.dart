// Disposable real-provider TUI assembly. Never part of release artifacts.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/entrypoint.dart';

const _identity = String.fromEnvironment('keybay.application_id');
const _rp = String.fromEnvironment('keybay.hardware_rp_id');
const _markerName = 'hardware-test/marker';
const _marker = 'Disposable hardware TUI test';
final _events = <Map<String, Object?>>[];

void _record(String event, [Map<String, Object?> fields = const {}]) {
  _events.add({
    'event': event,
    'time': DateTime.now().toUtc().toIso8601String(),
    ...fields,
  });
  final directory = File(Platform.resolvedExecutable).parent;
  final target = File('${directory.path}/receipt-$pid.json');
  final stage = File('${target.path}.tmp');
  stage.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'applicationId': _identity,
      'rpId': _rp,
      'processId': pid,
      'events': _events,
    }),
    flush: true,
  );
  stage.renameSync(target.path);
}

Future<void> main(List<String> arguments) async {
  if (!_identity.startsWith('keybay-cli-hardware-test-') ||
      !_rp.endsWith('.test')) {
    stderr.writeln(
      'This harness requires its disposable build identity and RP.',
    );
    exitCode = 64;
    return;
  }
  _record('started');
  exitCode = await runKeybay(
    arguments.isEmpty ? ['open'] : arguments,
    openSession: ({credential, methodId, cancellation}) async {
      KeybaySession? session;
      try {
        session = await Keybay.open(
          credential: credential,
          methodId: methodId,
          cancellation: cancellation,
        );
        if (session.wasInitialized) await session.set(_markerName, _marker);
        final matched = await session.get(_markerName) == _marker;
        _record('opened', {
          'via': credential is PasskeyCredential
              ? credential.route.name
              : credential == null
              ? 'platform'
              : 'passphrase',
          'markerMatched': matched,
          'methodCount': (await session.auth.list()).length,
        });
        if (!matched) throw StateError('Disposable marker mismatch');
        return _RecordedSession(session);
      } on Object catch (error) {
        await session?.close();
        _record('openFailed', {
          'code': error is KeybayException ? error.code.name : 'fixtureFailure',
        });
        rethrow;
      }
    },
  );
  _record('exited', {'exitCode': exitCode});
}

final class _RecordedSession implements KeybaySession {
  _RecordedSession(this.inner);
  final KeybaySession inner;
  @override
  bool get wasInitialized => inner.wasInitialized;
  @override
  bool get isClosed => inner.isClosed;
  @override
  KeybayAuthManager get auth => _RecordedAuth(inner.auth);
  @override
  Future<String?> get(String key) => inner.get(key);
  @override
  Future<void> set(String key, String value) => inner.set(key, value);
  @override
  Future<Uint8List?> getBytes(String key) => inner.getBytes(key);
  @override
  Future<Map<String, Uint8List?>> getManyBytes(Iterable<String> keys) =>
      inner.getManyBytes(keys);
  @override
  Future<List<String>> listKeys() => inner.listKeys();
  @override
  Future<void> setBytes(String key, Uint8List value) =>
      inner.setBytes(key, value);
  @override
  Future<bool> contains(String key) => inner.contains(key);
  @override
  Future<bool> delete(String key) => inner.delete(key);
  @override
  Future<void> clearAll() => inner.clearAll();
  @override
  Future<void> close() => inner.close();
}

final class _RecordedAuth implements KeybayAuthManager {
  _RecordedAuth(this.inner);
  final KeybayAuthManager inner;
  @override
  Future<List<AuthMethod>> list() => inner.list();
  @override
  Future<AuthMethod> add(
    KeybayCredential credential, {
    String? label,
    PasskeyCancellation? cancellation,
  }) async {
    try {
      final method = await inner.add(
        credential,
        label: label,
        cancellation: cancellation,
      );
      _record('methodAdded', {
        'kind': credential is PasskeyCredential
            ? credential.route.name
            : 'passphrase',
      });
      return method;
    } on KeybayException catch (error) {
      _record('addFailed', {
        'code': error.code.name,
        'passkeyCode': error.passkeyCode?.name,
      });
      rethrow;
    }
  }

  @override
  Future<void> remove(AuthMethod method) async {
    await inner.remove(method);
    _record('methodRemoved');
  }
}
