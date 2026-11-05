import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mandai_merchandise/main.dart';

void main() {
  testWidgets('login screen is rendered after tapping Log in', (tester) async {
    // Exercise the actual storefront-to-login navigation, without waiting for
    // the splash transition or making a real network request.
    await tester.pumpWidget(const MaterialApp(home: Shell()));

    final loginAction = find.widgetWithText(TextButton, 'Log in');
    expect(loginAction, findsOneWidget);
    await tester.tap(loginAction);
    await tester.pump();

    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log In'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3)); // Header search + credentials.

    // Shell.load() starts a 5-second precache timeout during initial landing.
    // Advance the fake clock so no timeout timer survives widget test teardown.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  });
}
