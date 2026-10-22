import 'dart:io';

import 'package:edushelf_reading_application/models/syllabus_content.dart';
import 'package:edushelf_reading_application/services/syllabus_text.dart';
import 'package:flutter_test/flutter_test.dart';

SyllabusContent read(String name) => SyllabusContent.fromPdfLines(
    extractPdfLines(File('test/fixtures/$name').readAsBytesSync()));

void main() {
  // Totals printed in each PDF ("Total units listed: N").
  const expected = {
    'BSIT_Curriculum_Outline.pdf': (
      title: 'BACHELOR OF SCIENCE IN INFORMATION TECHNOLOGY',
      sections: 9,
      units: 167.0,
    ),
    'BSA_Curriculum_Outline.pdf': (
      title: 'BACHELOR OF SCIENCE IN ACCOUNTANCY',
      sections: 8,
      units: 188.0,
    ),
    'BSBA_Curriculum_Outline.pdf': (
      title: 'BACHELOR OF SCIENCE IN BUSINESS ADMINISTRATION (MAJOR IN '
          'MARKETING MANAGEMENT)',
      sections: 8,
      units: 134.0,
    ),
    'BSOA_Curriculum_Outline.pdf': (
      title: 'BACHELOR OF SCIENCE IN OFFICE ADMINISTRATION',
      sections: 8,
      units: 131.0,
    ),
  };

  for (final e in expected.entries) {
    test('fills ${e.key} completely from the PDF', () {
      final c = read(e.key);
      expect(c.programTitle, e.value.title);
      expect(c.sections, hasLength(e.value.sections));
      expect(c.totalUnits, e.value.units,
          reason: 'every course row was read with its units');
      expect(c.notes, contains('CMO No.'));
      expect(c.sections.first.title, 'First Year - First Semester');
    });
  }

  test('BSIT details: section totals and tricky rows', () {
    final c = read('BSIT_Curriculum_Outline.pdf');
    expect(c.sections.map((s) => s.totalUnits),
        [23, 23, 23, 23, 21, 21, 6, 21, 6]);
    expect(c.sections[6].title, 'Third Year - Midyear Term');

    final first = c.sections.first.courses;
    expect(first.first.code, 'IT 111');
    expect(first.first.title, 'Introduction to Computing');
    expect(first.last.code, 'NSTP 111');
    expect(first.last.title, 'National Service Training Program 1');
    expect(first.last.units, 3);
  });

  test('BSOA codes without spaces in names (GE 1, PATHFit 1)', () {
    final c = read('BSOA_Curriculum_Outline.pdf');
    final codes = c.sections.first.courses.map((x) => x.code).toList();
    expect(codes, contains('GE 1'));
    expect(codes, contains('PATHFit 1'));
  });

  test('JSON round-trip keeps everything', () {
    final c = read('BSA_Curriculum_Outline.pdf');
    final copy = SyllabusContent.fromJson(c.toJson());
    expect(copy.toJson(), c.toJson());
    expect(copy.courseCount, c.courseCount);
  });

  test('formatUnits', () {
    expect(formatUnits(3), '3');
    expect(formatUnits(1.5), '1.5');
  });
}
