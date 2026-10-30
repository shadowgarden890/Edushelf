import 'package:edushelf_reading_application/models/department.dart';
import 'package:edushelf_reading_application/models/user_session.dart';
import 'package:edushelf_reading_application/screen/admin/admin_dashboard_screen.dart';
import 'package:edushelf_reading_application/screen/admin/department_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Lays out the admin screens at desktop and phone sizes to catch
// overflows (a layout overflow fails the test).
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'http://localhost:9', publishableKey: 'test', debug: false);
  });

  final session = UserSession(
      idNumber: 'ADMIN-0001',
      fullName: 'Ana Admin',
      role: 'admin',
      department: 'ALL');

  final users = [
    for (var i = 1; i <= 4; i++)
      {
        'id_number': 'IT-2${i % 3 + 2}-0100$i',
        'full_name': 'Student Number $i',
        'role': 'student',
        'department': 'BSIT',
      },
    {
      'id_number': 'IT-T-00001',
      'full_name': 'Juan Dela Cruz',
      'role': 'instructor',
      'department': 'BSIT',
    },
    {
      'id_number': 'IT-T-00002',
      'full_name': 'Maria Santos',
      'role': 'instructor',
      'department': 'BSIT',
    },
  ];
  final materials = [
    for (var i = 1; i <= 5; i++)
      {
        'id': 'm$i',
        'title': 'Reading Material Number $i With A Long Title',
        'code': 'IT ${200 + i}',
        'program': 'BSIT',
        'year': ['1st Year', '2nd Year', '3rd Year'][i % 3],
        'term': '1st Sem',
        'instructor': i.isEven ? 'Juan Dela Cruz' : 'Maria Santos',
        'uploaded_by': i.isEven ? 'IT-T-00001' : 'IT-T-00002',
        'type': 'learning_material',
        'status': ['pending', 'approved', 'rejected'][i % 3],
        'uploaded_at': DateTime.now().toIso8601String(),
      },
    {
      'id': 's1',
      'title': 'BSIT Curriculum',
      'code': 'IT 000',
      'program': 'BSIT',
      'year': 'All Years',
      'term': 'All Terms',
      'instructor': 'Juan Dela Cruz',
      'uploaded_by': 'IT-T-00001',
      'type': 'syllabus',
      'status': 'approved',
      'uploaded_at': DateTime.now().toIso8601String(),
    },
  ];

  for (final size in [const Size(1400, 900), const Size(400, 860)]) {
    final w = size.width.toInt();

    testWidgets('admin dashboard lays out at $w', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: const Color(0xFF0B132B)),
          home: AdminDashboardScreen(session: session)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Homepage'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });

    testWidgets('department folders lay out at $w', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: DepartmentScreen(
          department: Department.all.first,
          users: Stream.value(users),
          materials: Stream.value(materials),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('BS Information Technology'), findsOneWidget);

      for (final folder in [
        'Students',
        'Faculty',
        'Syllabus',
        'Reading Materials'
      ]) {
        final f = find.text(folder);
        await tester.scrollUntilVisible(f, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(f);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // Inside a faculty member's folder: grouped by year.
      await tester.scrollUntilVisible(find.text('Reading Materials'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Reading Materials'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Juan Dela Cruz'));
      await tester.pumpAndSettle();
      expect(find.text('3rd Year'), findsOneWidget);
    });
  }
}
