import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay/keybay.dart';

const String _v2Key = 'integration/token';
const String _v2Value = 'public-v2-secret';
const String _passphrase = 'integration-passphrase';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) throw StateError('expected one operation');
  switch (arguments.single) {
    case 'initialize':
      return _initialize();
    case 'reopen':
      return _reopen();
    case 'reset':
      return Keybay.reset();
    default:
      throw StateError('unknown operation');
  }
}

Future<void> _initialize() async {
  final session = await Keybay.open();
  try {
    _require(session.wasInitialized, 'V2 state was not initialized');
    _require(await session.get(_v2Key) == null, 'unexpected initial V2 value');
    await session.set(_v2Key, _v2Value);
    final phrase = _phraseBytes();
    try {
      await session.auth.add(PassphraseCredential(phrase: phrase));
    } finally {
      _clear(phrase);
    }
  } finally {
    await session.close();
  }
}

Future<void> _reopen() async {
  KeybaySession? unexpected;
  try {
    unexpected = await Keybay.open();
  } on KeybayException catch (failure) {
    _require(
      failure.code == KeybayErrorCode.authRequired,
      'credential-free open returned the wrong failure',
    );
  }
  if (unexpected != null) {
    await unexpected.close();
    throw StateError('credential-free open unexpectedly succeeded');
  }

  final phrase = _phraseBytes();
  final KeybaySession session;
  try {
    session = await Keybay.open(
      credential: PassphraseCredential(phrase: phrase),
    );
  } finally {
    _clear(phrase);
  }
  try {
    _require(!session.wasInitialized, 'existing V2 state was reinitialized');
    _require(
      await session.get(_v2Key) == _v2Value,
      'persisted V2 value did not reopen',
    );
  } finally {
    await session.close();
  }
}

Uint8List _phraseBytes() => Uint8List.fromList(utf8.encode(_passphrase));

void _clear(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
