import 'dart:async';
import 'dart:js_interop';

import 'package:fleury_web/fleury_web.dart';
import 'package:keybay_cli/src/tui/clipboard_contract.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/screen.dart';
import 'package:web/web.dart' as web;

import 'store.dart';

Future<void> main() async {
  final host = web.document.getElementById('demo')! as web.HTMLElement;
  final status = web.document.getElementById('status')!;
  final restart =
      web.document.getElementById('restart')! as web.HTMLButtonElement;
  final placeholder =
      web.document.getElementById('placeholder')! as web.HTMLElement;
  MountedApp? surface;
  TuiModel? model;
  DemoStore? store;
  var changing = false;

  Future<void> dispose() async {
    final previous = model;
    model = null;
    final mounted = surface;
    surface = null;
    await mounted?.dispose();
    await previous?.close();
    previous?.dispose();
    store?.dispose();
    store = null;
  }

  Future<void> stop() async {
    await dispose();
    host.hidden = true.toJS;
    placeholder.hidden = false.toJS;
    placeholder.textContent = 'Demo closed. Start again whenever you like.';
    status.textContent = 'Temporary sample data';
    restart.textContent = 'Start demo';
  }

  Future<void> start({bool requestFocus = true}) async {
    if (changing) return;
    changing = true;
    restart.disabled = true;
    try {
      await dispose();
      final data = store = DemoStore();
      late final TuiModel current;
      current = TuiModel(
        openSession: data.open,
        resetStore: data.reset,
        authorize: () {},
        copyText: (text) async {
          try {
            await web.window.navigator.clipboard.writeText(text).toDart;
          } on Object {
            throw const TuiCopyException();
          }
        },
        onExit: () {
          if (identical(model, current)) unawaited(stop());
        },
        idleTimeout: null,
      );
      model = current;
      await current.open();
      placeholder.hidden = true.toJS;
      host.hidden = false.toJS;
      surface = await mountApp(
        () => KeybayTui(model: current),
        into: host,
        clipboard: DiscardClipboard(),
      );
      // Fleury initially captures the keyboard. An embedded demo should wait
      // for a click, while an explicit Start/Reset should keep that focus.
      if (!requestFocus) {
        (web.document.activeElement as web.HTMLElement?)?.blur();
      }
      status.textContent = 'Temporary sample data';
      restart.textContent = 'Reset demo';
    } on Object {
      await dispose();
      host.hidden = true.toJS;
      placeholder.hidden = false.toJS;
      placeholder.textContent =
          'The demo could not load. Try starting it again.';
      restart.textContent = 'Start demo';
    } finally {
      changing = false;
      restart.disabled = false;
    }
  }

  restart.addEventListener('click', ((web.Event _) => unawaited(start())).toJS);
  web.window.addEventListener('blur', ((web.Event _) => model?.conceal()).toJS);
  web.window.addEventListener(
    'resize',
    ((web.Event _) => model?.conceal()).toJS,
  );
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.hidden) model?.conceal();
    }).toJS,
  );
  web.window.addEventListener(
    'pagehide',
    ((web.PageTransitionEvent event) {
      if (event.persisted) {
        model?.conceal();
      } else {
        unawaited(dispose());
      }
    }).toJS,
  );
  await start(requestFocus: false);
}
