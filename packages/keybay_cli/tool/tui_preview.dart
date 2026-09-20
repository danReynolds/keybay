// Local UX preview: the real TUI and model with an in-memory test store.
// This entrypoint is never used by the production CLI or release artifacts.
import 'dart:convert';

import 'package:fleury/fleury.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_cli/src/tui/clipboard.dart';
import 'package:keybay_cli/src/tui/model.dart';
import 'package:keybay_cli/src/tui/screen.dart';

import '../../keybay/test/support/v2_test_keybay.dart';

Future<void> main(List<String> arguments) async {
  const options = {'--empty', '--locked', '--copy-fails'};
  if (arguments.any((argument) => !options.contains(argument))) {
    throw ArgumentError('Preview options: ${options.join(', ')}');
  }
  final store = V2TestKeybay(applicationId: 'dev.keybay.tui-preview');
  final seed = await store.open();
  if (!arguments.contains('--empty')) {
    for (final entry in const {
      'acme/api-key': 'demo_acme_key_for_ux_review',
      'acme/database-url': 'postgres://demo:example@localhost:5432/acme_dev',
      'acme/signing-key':
          '-----BEGIN DEMO KEY-----\nexample-line-one\nexample-line-two\n-----END DEMO KEY-----',
      'anthropic/api-key': 'sk-ant-demo-not-a-real-key',
      'aws/access-key-id': 'AKIA_DEMO_ONLY',
      'aws/secret-access-key': 'example-aws-secret-for-preview',
      'cloudflare/api-token': 'cloudflare-demo-token',
      'database/password': 'preview-only-database-password',
      'github/token': 'ghp_demo_not_a_real_token',
      'mailgun/api-key': 'key-demo-mailgun',
      'npm/token': 'npm_demo_not_a_real_token',
      'openai/api-key': 'sk-demo-not-a-real-key',
      'sentry/auth-token': 'sentry-demo-token',
      'stripe/test-key': 'sk_test_demo_for_ux_review',
      'vercel/token': 'vercel-demo-token',
      'webhook/signing-secret': 'whsec_demo_not_a_real_secret',
    }.entries) {
      await seed.set(entry.key, entry.value);
    }
  }
  if (arguments.contains('--locked')) {
    final phrase = utf8.encode('preview');
    try {
      await seed.auth.add(PassphraseCredential(phrase: phrase));
    } finally {
      phrase.fillRange(0, phrase.length, 0);
    }
  }
  await seed.close();

  final model = TuiModel(
    openSession: store.open,
    resetStore: store.reset,
    authorize: () {},
    // Exercise the normal feedback path without writing a real clipboard.
    copyText: (_) async {
      if (arguments.contains('--copy-fails')) throw const TuiCopyException();
    },
    onExit: requestExit,
    idleTimeout: null,
  );
  try {
    await model.open();
    await runApp(
      KeybayTui(model: model),
      enableHotReload: false,
      debug: const DebugConfig(enabled: false),
      clipboard: DiscardClipboard(),
      onEvent: (event) {
        if (event is ResizeEvent ||
            event is TerminalFocusEvent && !event.focused) {
          model.conceal();
        }
        return null;
      },
    );
  } finally {
    await model.close();
    model.dispose();
    await store.dispose();
  }
}
