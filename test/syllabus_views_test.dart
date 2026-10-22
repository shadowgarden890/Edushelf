import 'dart:io';

import 'package:edushelf_reading_application/models/syllabus_content.dart';
import 'package:edushelf_reading_application/models/user_session.dart';
import 'package:edushelf_reading_application/screen/teachers/syllabus_editor_screen.dart';
import 'package:edushelf_reading_application/services/syllabus_text.dart';
import 'package:edushelf_reading_application/widgets/syllabus_content_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bsit = SyllabusContent.fromPdfLines(extractPdfLines(
      File('test/fixtures/BSIT_Curriculum_Outline.pdf').readAsBytesSync()));

  Future<void> pumpView(WidgetTester tester, {String query = ''}) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SyllabusContentView(
            content: bsit, header: const Text('HEADER'), query: query),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows semesters with totals; first one open', (tester) async {
    await pumpView(tester);
    expect(find.text('9 semesters • 56 courses • 167 units'), findsOneWidget);
    expect(find.text('First Year - First Semester'), findsOneWidget);
    expect(find.text('Introduction to Computing'), findsOneWidget,
        reason: 'first semester is expanded');
    expect(find.text('Cloud Computing'), findsNothing,
        reason: 'other semesters start collapsed');
    await tester.scrollUntilVisible(find.text('Total units: 167'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Total units: 167'), findsOneWidget);
  });

  testWidgets('search finds a course to take in advance', (tester) async {
    await pumpView(tester, query: 'IT 323');
    expect(find.text('1 course found'), findsOneWidget);
    expect(find.text('Third Year - Second Semester'), findsOneWidget);
    expect(find.text('Information Assurance and Security'), findsOneWidget);
    expect(find.text('First Year - First Semester'), findsNothing);
  });

  testWidgets('search by title, and no matches', (tester) async {
    await pumpView(tester, query: 'networking');
    expect(find.text('4 courses found'), findsOneWidget);
    await pumpView(tester, query: 'basket weaving');
    expect(find.text('No course matches "basket weaving".'), findsOneWidget);
  });

  testWidgets('editor: add a course and the units total updates',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SyllabusEditorScreen(
        session: UserSession(
            idNumber: 'IT-T-00001',
            fullName: 'Prof. Ana Reyes',
            role: 'instructor',
            department: 'BSIT'),
      ),
    ));

    expect(find.text('BSIT Curriculum Outline'), findsOneWidget);
    expect(find.text('Total: 3 units'), findsOneWidget,
        reason: 'one empty course row with 3 units by default');

    await tester.tap(find.text('Add course'));
    await tester.pump();
    expect(find.text('Total: 6 units'), findsOneWidget);
    expect(find.text('Fill from PDF'), findsOneWidget);
  });
}
