import 'package:edushelf_reading_application/models/user_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSession.parseId', () {
    test('student IDs map to student role and department', () {
      expect(UserSession.parseId('IT-23-01003'),
          {'role': 'student', 'department': 'BSIT'});
      expect(UserSession.parseId('BA-21-00001'),
          {'role': 'student', 'department': 'BSBA'});
      expect(UserSession.parseId('AC-24-12345'),
          {'role': 'student', 'department': 'BSA'});
      expect(UserSession.parseId('OA-22-00042'),
          {'role': 'student', 'department': 'BSOA'});
    });

    test('faculty IDs map to instructor role', () {
      expect(UserSession.parseId('IT-T-00001'),
          {'role': 'instructor', 'department': 'BSIT'});
    });

    test('admin IDs map to admin role', () {
      expect(UserSession.parseId('ADMIN-0001'),
          {'role': 'admin', 'department': 'ALL'});
    });

    test('is case- and whitespace-insensitive', () {
      expect(UserSession.parseId('  it-23-01003 '),
          {'role': 'student', 'department': 'BSIT'});
    });

    test('rejects malformed IDs', () {
      for (final id in [
        '',
        'IT2301003',
        'XX-23-01003',
        'IT-2023-01003',
        'IT-AB-01003',
        'IT-23',
        'ADMIN',
        'IT-23-01003-1',
      ]) {
        expect(UserSession.parseId(id), isNull, reason: id);
      }
    });
  });

  test('fromMap and toMap round-trip', () {
    final map = {
      'id_number': 'IT-T-00001',
      'full_name': 'Jane Doe',
      'role': 'instructor',
      'department': 'BSIT',
    };
    expect(UserSession.fromMap(map).toMap(), map);
  });
}
