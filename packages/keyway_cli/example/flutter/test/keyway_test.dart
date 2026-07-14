import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyway_flutter_example/main.dart';

void main() {
  testWidgets('renders the disposable credential received from the host', (
    tester,
  ) async {
    final fromKeyway =
        Platform.environment['KEYWAY_EXAMPLE_INTEGRATION'] == '1';
    final environment = fromKeyway
        ? Platform.environment
        : const {
            'API_BASE_URL': 'https://staging.example.com',
            'FLUTTER_EXAMPLE_API_TOKEN': 'disposable-test-token',
          };
    final token = environment['FLUTTER_EXAMPLE_API_TOKEN'];

    expect(environment['API_BASE_URL'], 'https://staging.example.com');
    expect(
      token,
      isNotEmpty,
      reason: 'run this test through keyway from the example directory',
    );

    await tester.pumpWidget(KeywayExampleApp(environment: environment));

    expect(find.text('https://staging.example.com'), findsOneWidget);
    expect(find.text(token!), findsOneWidget);
    expect(find.byKey(const ValueKey('api-token-value')), findsOneWidget);
    expect(
      find.textContaining('Never use a production credential'),
      findsOneWidget,
    );
  });
}
