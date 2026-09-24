import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keybay/keybay.dart';
import 'package:keybay_demo/src/app.dart';
import 'package:keybay_demo/src/vault_backend.dart';

// The SDK's production store engine over disposable in-memory boundaries.
import '../../../packages/keybay/test/support/v2_test_keybay.dart';

final class _MemoryBackend implements VaultBackend {
  final keybay = V2TestKeybay(
    applicationId: 'io.github.danreynolds.keybay.demo.test',
  );

  @override
  Future<KeybaySession> open({KeybayCredential? credential}) =>
      keybay.open(credential: credential);

  @override
  Future<void> reset() => keybay.reset();
}

void main() {
  // Each test gets a fresh in-memory store. Disposing it while the app still
  // holds a session would wait on that session, so none is disposed here.
  late _MemoryBackend backend;

  setUp(() => backend = _MemoryBackend());

  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(KeybayDemoApp(backend: backend));
    await tester.pumpAndSettle();
  }

  Future<void> addSecret(WidgetTester tester, String name, String value) async {
    await tester.tap(find.byTooltip('Add secret'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
    await tester.enterText(find.widgetWithText(TextField, 'Value'), value);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  Future<void> revealSecret(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new store opens empty under device protection', (
    tester,
  ) async {
    await start(tester);
    expect(find.text('Device protection only'), findsOneWidget);
    expect(
      find.text('A new store was created on this device.'),
      findsOneWidget,
    );
    expect(find.text('No secrets yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('secrets are saved, revealed, edited and deleted', (
    tester,
  ) async {
    await start(tester);
    await addSecret(tester, 'api/token', 'first-value');
    expect(find.text('api/token'), findsOneWidget);

    await tester.tap(find.text('api/token'));
    await tester.pumpAndSettle();
    expect(find.text('first-value'), findsNothing);
    await tester.tap(find.text('Reveal'));
    await tester.pumpAndSettle();
    expect(find.text('first-value'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Value'),
      'second-value',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await revealSecret(tester, 'api/token');
    expect(find.text('second-value'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('api/token'), findsNothing);
    expect(find.text('No secrets yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('a passphrase is required to open the store again', (
    tester,
  ) async {
    await start(tester);
    await addSecret(tester, 'db/password', 'hunter2');

    await tester.tap(find.byTooltip('Protection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add passphrase'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New passphrase'),
      'correct horse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat passphrase'),
      'correct horse',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Passphrase and device protection'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('The vault is closed.'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your passphrase'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong passphrase.'), findsOneWidget);
    expect(find.text('db/password'), findsNothing);

    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await revealSecret(tester, 'db/password');
    expect(find.text('hunter2'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // Dismiss the sheet.
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Protection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove passphrase'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Device protection only'), findsOneWidget);
  });

  testWidgets('leaving the foreground covers and closes the vault', (
    tester,
  ) async {
    await start(tester);
    await addSecret(tester, 'wifi', 'swordfish');
    await revealSecret(tester, 'wifi');
    expect(find.text('swordfish'), findsOneWidget);

    final cover = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == Colors.black,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(cover, findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // Nothing is drawn in the background. The first frame back, the same one
    // that lifts the cover, must not show the value or its sheet.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cover, findsNothing);
    expect(find.text('swordfish'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('wifi'), findsOneWidget);
    expect(find.text('swordfish'), findsNothing);
  });

  testWidgets('reset deletes every secret', (tester) async {
    await start(tester);
    await addSecret(tester, 'a', '1');
    await tester.tap(find.byTooltip('Protection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset store'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(find.text('No secrets yet. Tap + to add one.'), findsOneWidget);
    expect(
      find.text('A new store was created on this device.'),
      findsOneWidget,
    );
  });
}
