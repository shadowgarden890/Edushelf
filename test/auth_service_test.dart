import 'package:edushelf_reading_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService.emailForId', () {
    test('maps ID numbers to lower-case internal addresses', () {
      expect(AuthService.emailForId(' IT-23-01003 '),
          'it-23-01003@${AuthService.authEmailDomain}');
    });
  });

  group('AuthService.hashPassword', () {
    const salt = 'c2FsdHNhbHRzYWx0c2FsdA=='; // "saltsaltsaltsalt"

    test('is deterministic for the same password and salt', () {
      expect(AuthService.hashPassword('secret123', salt),
          AuthService.hashPassword('secret123', salt));
    });

    test('differs for different passwords or salts', () {
      final hash = AuthService.hashPassword('secret123', salt);
      expect(AuthService.hashPassword('secret124', salt), isNot(hash));
      expect(AuthService.hashPassword('secret123', 'b3RoZXJzYWx0b3RoZXI='),
          isNot(hash));
    });

    test('never contains the plaintext password', () {
      expect(AuthService.hashPassword('secret123', salt),
          isNot(contains('secret123')));
    });
  });
}
