import 'dart:convert';
import 'dart:typed_data';

import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/store.dart';
import 'package:test/test.dart';

import '../site/demo/store.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test(
    'the demo drives the shared model through reveal, edit and close',
    () async {
      final data = DemoStore();
      var exited = false;
      final model = TuiModel(
        openSession: data.open,
        resetStore: data.reset,
        authorize: () {},
        onExit: () => exited = true,
        idleTimeout: null,
      );
      await model.open();
      expect(model.view, TuiView.browse);
      model.select('acme-example/openai-api-key');
      await model.read();
      expect(model.valueText, 'sk-demo-not-a-real-key');
      model.hide();
      expect(model.valueText, isEmpty);
      await model.read(edit: true);
      expect(model.view, TuiView.edit);
      expect(model.takeEditText(), 'sk-demo-not-a-real-key');
      final value = bytes('changed-demo-value');
      await model.save('acme-example/openai-api-key', value, replace: true);
      expect(value, everyElement(0));
      await model.read();
      expect(model.valueText, 'changed-demo-value');
      await model.close();
      expect(exited, isTrue);
      expect(model.valueText, isEmpty);
      model.dispose();
      data.dispose();
    },
  );

  test('demo input is copied before callers clear borrowed buffers', () async {
    final store = DemoStore();
    final session = await store.open();
    final value = bytes('sample');
    final writing = session.setBytes('test/key', value);
    value.fillRange(0, value.length, 0);
    await writing;
    expect(utf8.decode((await session.getBytes('test/key'))!), 'sample');
    final phrase = bytes('demo-password');
    final changing = session.changePassphrase(phrase, replacing: false);
    phrase.fillRange(0, phrase.length, 0);
    await changing;
    await session.close();
    await expectLater(
      store.open(),
      throwsA(
        isA<TuiStoreException>().having(
          (e) => e.unlock,
          'unlock',
          TuiUnlockFailure.missing,
        ),
      ),
    );
    await expectLater(
      store.open(phrase: bytes('wrong')),
      throwsA(
        isA<TuiStoreException>().having(
          (e) => e.unlock,
          'unlock',
          TuiUnlockFailure.incorrect,
        ),
      ),
    );
    final opened = await store.open(phrase: bytes('demo-password'));
    expect(await opened.passphraseId(), isNotNull);
    await opened.close();
    store.dispose();
  });

  test(
    'reset invalidates old sessions and demo instances share no data',
    () async {
      final first = DemoStore();
      final second = DemoStore();
      final session = await first.open();
      await session.clearAll();
      final separate = await second.open();
      expect(await separate.listKeys(), hasLength(5));
      await first.reset();
      await expectLater(session.listKeys(), throwsA(isA<TuiStoreException>()));
      final fresh = await first.open();
      expect(fresh.wasInitialized, isTrue);
      expect(await fresh.listKeys(), isEmpty);
      await fresh.close();
      await separate.close();
      first.dispose();
      second.dispose();
    },
  );
}
