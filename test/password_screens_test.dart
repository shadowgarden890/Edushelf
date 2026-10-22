import 'package:edushelf_reading_application/models/user_session.dart';
import 'package:edushelf_reading_application/screen/force_password_change_screen.dart';
import 'package:edushelf_reading_application/screen/forgot_password_screen.dart';
import 'package:edushelf_reading_application/screen/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login screen links to Forgot password', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.enterText(find.byType(TextField).first, 'it-23-01003');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('it-23-01003'), findsOneWidget,
        reason: 'ID typed on the login screen is carried over');
  });

  testWidgets('forgot password requires ID and full name', (tester) async {
    // A phone-sized screen, tall enough to show the whole form.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
    await tester.tap(find.text('Send request'));
    await tester.pump();

    expect(find.text('Enter your ID number'), findsOneWidget);
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('At least 6 characters'), findsNothing,
        reason: 'the admin sets the temporary password, not the user');
  });

  testWidgets(
      'admins are told to use their recovery password instead of '
      'requesting a reset', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
        home: ForgotPasswordScreen(initialIdNumber: 'ADMIN-0001')));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Main Admin');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();

    expect(find.text('Use your recovery password'), findsOneWidget);
    expect(find.text('Request sent'), findsNothing);
  });

  testWidgets('first-login screen rejects reusing the temporary password',
      (tester) async {
    var changed = false;
    await tester.pumpWidget(MaterialApp(
      home: ForcePasswordChangeScreen(
        session: UserSession(
            idNumber: 'IT-23-01003',
            fullName: 'Juan Dela Cruz',
            role: 'student',
            department: 'BSIT'),
        temporaryPassword: 'Read-4827-km',
        onChanged: () => changed = true,
      ),
    ));

    expect(find.text('Welcome, Juan Dela Cruz!'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Read-4827-km');
    await tester.enterText(fields.at(1), 'Read-4827-km');
    await tester.tap(find.text('Set password and continue'));
    await tester.pump();
    expect(find.text('Choose a different password'), findsOneWidget);

    await tester.enterText(fields.at(0), 'mynewpass');
    await tester.enterText(fields.at(1), 'different');
    await tester.tap(find.text('Set password and continue'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(changed, isFalse);
  });
}
