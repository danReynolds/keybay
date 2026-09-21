import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay_cli/src/tui/store.dart';

/// Website-only sample data. This is not encrypted storage and is never used
/// by the CLI. No browser storage, native providers or network are involved.
final class DemoStore {
  DemoStore() {
    for (final entry in const {
      'acme-example/openai-api-key': 'sk-demo-not-a-real-key',
      'acme-example/database-url': 'postgres://demo:example@localhost/acme',
      'github/token': 'ghp_demo_not_a_real_token',
      'stripe/test-key': 'sk_test_demo_only',
      'webhook/signing-secret': 'whsec_demo_not_a_real_secret',
    }.entries) {
      _values[entry.key] = Uint8List.fromList(utf8.encode(entry.value));
    }
  }

  final _values = <String, Uint8List>{};
  Uint8List? _phrase;
  bool _initialized = true;
  int _generation = 0;

  Future<TuiSession> open({Uint8List? phrase}) {
    // Validate borrowed input synchronously, before TuiModel clears it.
    if (_phrase != null) {
      if (phrase == null) {
        return Future.error(
          const TuiStoreException('', unlock: TuiUnlockFailure.missing),
        );
      }
      if (phrase.length != _phrase!.length ||
          !Iterable<int>.generate(
            phrase.length,
          ).every((i) => phrase[i] == _phrase![i])) {
        return Future.error(
          const TuiStoreException('', unlock: TuiUnlockFailure.incorrect),
        );
      }
    }
    final fresh = !_initialized;
    _initialized = true;
    return Future.value(_DemoSession(this, _generation, fresh));
  }

  Future<void> reset() async {
    dispose();
    _initialized = false;
  }

  void dispose() {
    for (final value in _values.values) {
      value.fillRange(0, value.length, 0);
    }
    _values.clear();
    _phrase?.fillRange(0, _phrase!.length, 0);
    _phrase = null;
    _generation++;
  }
}

final class _DemoSession implements TuiSession {
  _DemoSession(this.store, this.generation, this.wasInitialized);
  final DemoStore store;
  final int generation;
  @override
  final bool wasInitialized;
  bool closed = false;

  void check() {
    if (closed || generation != store._generation) {
      throw const TuiStoreException(
        'Demo session closed.',
        invalidatesSession: true,
      );
    }
  }

  @override
  Future<List<String>> listKeys() async {
    check();
    return store._values.keys.toList()..sort();
  }

  @override
  Future<String?> passphraseId() async {
    check();
    return store._phrase == null ? null : 'demo-passphrase';
  }

  @override
  Future<Uint8List?> getBytes(String key) async {
    check();
    final value = store._values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> setBytes(String key, Uint8List value) async {
    check();
    // Snapshot before returning, just like the native adapter contract.
    final copy = Uint8List.fromList(value);
    final old = store._values[key];
    old?.fillRange(0, old.length, 0);
    store._values[key] = copy;
  }

  @override
  Future<bool> delete(String key) async {
    check();
    final value = store._values.remove(key);
    value?.fillRange(0, value.length, 0);
    return value != null;
  }

  @override
  Future<void> clearAll() async {
    check();
    for (final key in store._values.keys.toList()) {
      await delete(key);
    }
  }

  @override
  Future<void> changePassphrase(
    Uint8List phrase, {
    required bool replacing,
  }) async {
    check();
    final copy = Uint8List.fromList(phrase);
    store._phrase?.fillRange(0, store._phrase!.length, 0);
    store._phrase = copy;
  }

  @override
  Future<void> removePassphrase(String id) async {
    check();
    store._phrase?.fillRange(0, store._phrase!.length, 0);
    store._phrase = null;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
