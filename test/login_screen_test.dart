import 'package:edushelf_reading_application/screen/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows an error when signing in with empty fields',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ID Number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Please enter your ID and Password.'), findsOneWidget);
  });

  testWidgets('has no sign-up; accounts come from the admin', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Sign Up'), findsNothing);
    expect(find.text('Request an account'), findsNothing);
    expect(find.textContaining('contact the school admin'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });
}
