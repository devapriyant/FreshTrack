import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshtrack/main.dart';

void main() {
  testWidgets('ErrorSetupScreen displays configuration requirement message', (
    WidgetTester tester,
  ) async {
    // Build our screen and trigger a frame.
    await tester.pumpWidget(
      const MaterialApp(home: ErrorSetupScreen(message: 'Update .env file')),
    );

    // Verify that our setup warning is displayed
    expect(find.text('Configuration Required'), findsOneWidget);
    expect(find.text('Update .env file'), findsOneWidget);
  });
}
