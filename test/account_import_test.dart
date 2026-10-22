import 'package:edushelf_reading_application/services/account_import.dart';
import 'package:edushelf_reading_application/services/credential_slips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCsv', () {
    test('handles quotes, escaped quotes, commas and CRLF', () {
      final rows =
          parseCsv('a,b\r\n"Dela Cruz, Juan","He said ""hi"""\r\n\r\nlast,row');
      expect(rows, [
        ['a', 'b'],
        ['Dela Cruz, Juan', 'He said "hi"'],
        ['last', 'row'],
      ]);
    });

    test('strips the Excel byte-order mark', () {
      expect(parseCsv('\uFEFFID Number,Full Name\n'), [
        ['ID Number', 'Full Name']
      ]);
    });
  });

  group('readAccountsCsv', () {
    test('finds columns by header in any order', () {
      final rows = readAccountsCsv(
          'Full Name,Section,ID Number\nJuan Dela Cruz,A,it-23-01003\n');
      expect(rows.single.idNumber, 'IT-23-01003');
      expect(rows.single.fullName, 'Juan Dela Cruz');
      expect(rows.single.isValid, isTrue);
      expect(rows.single.parsed, {'role': 'student', 'department': 'BSIT'});
    });

    test('without a header, uses column 1 = ID and column 2 = name', () {
      final rows = readAccountsCsv('IT-T-00002,Prof. Ana Reyes\n');
      expect(rows.single.isValid, isTrue);
      expect(rows.single.parsed!['role'], 'instructor');
    });

    test('flags bad rows with the reason and line number', () {
      final rows = readAccountsCsv('ID Number,Full Name\n'
          'IT-23-01003,Juan Dela Cruz\n'
          'XX-99,Bad Format\n'
          'BA-24-00015,\n'
          'it-23-01003,Same ID Again\n'
          ',No ID\n');
      expect(rows.map((r) => r.error), [
        null,
        'Invalid ID format',
        'Missing full name',
        'Duplicate ID in this file',
        'Missing ID number',
      ]);
      expect(rows[1].line, 3);
    });

    test('collapses extra spaces in names', () {
      final rows = readAccountsCsv('IT-23-01003,  Juan   Dela  Cruz \n');
      expect(rows.single.fullName, 'Juan Dela Cruz');
    });

    test('reads an optional email column', () {
      final rows = readAccountsCsv('ID Number,Full Name,Email\n'
          'IT-23-01003,Juan Dela Cruz,juan@school.edu.ph\n'
          'BA-24-00015,Maria Santos,\n'
          'IT-T-00002,Ana Reyes,not-an-email\n');
      expect(rows[0].email, 'juan@school.edu.ph');
      expect(rows[0].isValid, isTrue);
      expect(rows[1].email, isNull);
      expect(rows[1].isValid, isTrue, reason: 'email is optional');
      expect(rows[2].error, 'Invalid email "not-an-email"');
    });

    test('without a header, column 3 is the email', () {
      final rows = readAccountsCsv('IT-23-01003,Juan Dela Cruz,juan@x.com\n');
      expect(rows.single.email, 'juan@x.com');
    });

    test('a header without an email column means no emails', () {
      final rows = readAccountsCsv('ID Number,Full Name,Section\n'
          'IT-23-01003,Juan Dela Cruz,A\n');
      expect(rows.single.email, isNull);
      expect(rows.single.isValid, isTrue);
    });

    test('the template file is valid', () {
      final rows = readAccountsCsv(accountsCsvTemplate);
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.isValid), isTrue);
    });
  });

  group('credentials', () {
    const creds = [
      AccountCredentials(
          fullName: 'Dela Cruz, Juan',
          idNumber: 'IT-23-01003',
          password: 'Read-4827-km'),
      AccountCredentials(
          fullName: 'Maria Santos',
          idNumber: 'BA-24-00015',
          password: 'Book-2345-ab'),
    ];

    test('CSV export round-trips through the importer', () {
      final csv = credentialsToCsv(creds);
      expect(csv, startsWith('id_number,full_name,temporary_password'));
      final rows = parseCsv(csv);
      expect(rows[1], ['IT-23-01003', 'Dela Cruz, Juan', 'Read-4827-km', '']);
    });

    test('share text includes the login details', () {
      expect(creds.first.shareText, contains('IT-23-01003'));
      expect(creds.first.shareText, contains('Read-4827-km'));
    });

    test('login slips PDF is generated (8 per page)', () async {
      final many = List.generate(
          9,
          (i) => AccountCredentials(
              fullName: 'Student $i',
              idNumber: 'IT-23-0000$i',
              password: 'Read-2345-ab'));
      final bytes = await buildCredentialSlipsPdf(many);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(
          RegExp(r'/Type\s*/Page[^s]')
              .allMatches(String.fromCharCodes(bytes))
              .length,
          2);
    });
  });
}
