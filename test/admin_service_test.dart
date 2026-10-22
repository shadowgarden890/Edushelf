import 'package:edushelf_reading_application/services/admin_service.dart';
import 'package:edushelf_reading_application/widgets/request_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminService.generatePassword', () {
    test('is long enough and easy to read', () {
      for (var i = 0; i < 50; i++) {
        final password = AdminService.generatePassword();
        expect(password.length, greaterThanOrEqualTo(6));
        expect(password, matches(RegExp(r'^[A-Z][a-z]+-[2-9]{4}-[a-z]{2}$')));
        // The random part avoids look-alike characters (0/O, 1/l).
        final random = password.substring(password.indexOf('-'));
        expect(random, isNot(matches(RegExp('[01lo]'))));
      }
    });

    test('varies between calls', () {
      final passwords = {
        for (var i = 0; i < 20; i++) AdminService.generatePassword()
      };
      expect(passwords.length, greaterThan(15));
    });
  });

  test('server errors become readable messages', () {
    expect(AdminService.friendlyError('ID already registered: IT-23-01003'),
        'This ID number already has an account.');
    expect(AdminService.friendlyError('Invalid ID format: XX-1'),
        'Invalid ID number format.');
    expect(AdminService.friendlyError('Only admins can create accounts'),
        'Only admins can manage accounts.');
    expect(
        AdminService.friendlyError(
            'Could not find the function public.admin_create_user'),
        'Account management is not set up on the server yet.');
  });

  test('contact must be an email or a phone number', () {
    for (final ok in [
      'juan@school.edu.ph',
      '09171234567',
      '+63 917 123 4567',
      '(02) 8123-4567',
    ]) {
      expect(isValidContact(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'abc', 'juan@', '12345', 'juan at gmail']) {
      expect(isValidContact(bad), isFalse, reason: bad);
    }
  });
}
