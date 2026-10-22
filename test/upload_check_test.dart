import 'dart:typed_data';

import 'package:edushelf_reading_application/services/upload_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

PlatformFile _file(String name, int size) =>
    PlatformFile(name: name, size: size);

void main() {
  test('correct file credentials pass', () {
    expect(
        UploadService.checkCredentials(
            file: _file('module.pdf', 2048),
            title: 'Competency Appraisal 1',
            code: 'ITP411'),
        isEmpty);
    for (final code in ['IT 201', 'ACC-101', 'ITE322', 'mktg 101']) {
      expect(
          UploadService.checkCredentials(
              file: _file('a.pdf', 10), title: 'T', code: code),
          isEmpty,
          reason: code);
    }
  });

  test('every problem is listed so the faculty can revise', () {
    final problems = UploadService.checkCredentials(
        file: _file('notes.docx', 0), title: ' ', code: 'hello');
    expect(problems, hasLength(4));
    expect(problems.join(' '), contains('PDF'));
    expect(problems.join(' '), contains('empty'));
    expect(problems.join(' '), contains('title'));
    expect(problems.join(' '), contains('subject code'));
  });

  test('missing and oversized files are rejected', () {
    expect(
        UploadService.checkCredentials(file: null, title: 'T', code: 'IT 101'),
        ['Attach a PDF file.']);
    final big = UploadService.checkCredentials(
        file: _file('big.pdf', UploadService.maxFileBytes + 1),
        title: 'T',
        code: 'IT 101');
    expect(big.single, contains('limit'));
  });

  test('a renamed non-PDF file is detected by its content', () {
    expect(
        UploadService.looksLikePdf(
            Uint8List.fromList('%PDF-1.7 ...'.codeUnits)),
        isTrue);
    expect(
        UploadService.looksLikePdf(Uint8List.fromList('PK\x03\x04'.codeUnits)),
        isFalse);
  });
}
