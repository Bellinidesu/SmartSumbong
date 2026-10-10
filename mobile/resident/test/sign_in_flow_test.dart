// Signing in, on the real screens over the preview backend.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/app_harness.dart';

Future<void> signIn(WidgetTester tester, {required String role, required String number}) async {
  await tester.tap(find.text(role));
  await settle(tester);
  await tester.enterText(find.widgetWithText(TextField, 'Enter phone number'), number);
  await tester.enterText(find.widgetWithText(TextField, 'Enter password'), 'any-password');
  await tester.tap(find.text('Log In'));
  await settle(tester, rounds: 20);
}

void main() {
  testWidgets('a resident signs in and lands on Home', (tester) async {
    await bootApp(tester, role: null);
    expect(find.text('What’s your role?'), findsOneWidget);
    await signIn(tester, role: 'I’m a Resident', number: '0917 123 4567');
    expect(screenText().any((t) => t.startsWith('Welcome')), isTrue, reason: '${screenText()}');
    expect(find.text('Reports'), findsWidgets);
    await finish(tester);
  });

  testWidgets('a mistyped number is caught before anything is sent', (tester) async {
    final backend = await bootApp(tester, role: null);
    await signIn(tester, role: 'I’m a Resident', number: '12345');
    expect(screenText().any((t) => t.contains('09171234567')), isTrue, reason: '${screenText()}');
    expect(find.text('Log In'), findsOneWidget, reason: 'still on the sign-in screen');
    expect(backend, isNotNull);
    await finish(tester);
  });

  testWidgets('a tanod signs in and lands on the tanod home', (tester) async {
    await bootApp(tester, role: null);
    await signIn(tester, role: 'I’m a Tanod', number: '0927 126 9625');
    expect(find.text('Welcome, Kim Arcibal!'), findsOneWidget);
    expect(find.text('INCOMING DISPATCH'), findsOneWidget);
    expect(find.text('On Duty'), findsOneWidget);
    await finish(tester);
  });
}
