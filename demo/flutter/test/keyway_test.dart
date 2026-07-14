import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keyway_flutter_demo/main.dart';

void main() {
  testWidgets('receives configuration without rendering the credential', (
    tester,
  ) async {
    final environment = Platform.environment;
    final token = environment['FLUTTER_DEMO_API_TOKEN'];

    expect(environment['API_BASE_URL'], 'https://staging.example.com');
    expect(
      token,
      isNotEmpty,
      reason: 'run this test through keyway from the demo directory',
    );

    await tester.pumpWidget(KeywayDemoApp(environment: environment));

    expect(find.text('API: https://staging.example.com'), findsOneWidget);
    expect(find.text('API token: available'), findsOneWidget);
    expect(find.textContaining(token!), findsNothing);
  });
}
