import 'package:edushelf_reading_application/services/syllabus_text.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_test/flutter_test.dart';

PdfLine body(String t, {int page = 0}) => PdfLine(t, 11, false, page);
PdfLine big(String t) => PdfLine(t, 16, false, 0);
PdfLine bold(String t) => PdfLine(t, 11, true, 0);

void main() {
  test('big, bold or ALL-CAPS short lines become headings', () {
    final blocks = buildSyllabusBlocks([
      big('Information Assurance and Security'),
      body('This course introduces the CIA triad and'),
      body('basic cryptography.'),
      bold('Course Outcomes'),
      body('Students should be able to apply security'),
      body('principles.'),
      body('GRADING SYSTEM'),
      body('Exams 40%, Projects 60%.'),
    ]);

    expect(blocks.map((b) => b.isHeading), [
      true,
      false,
      true,
      false,
      true,
      false,
    ]);
    expect(blocks[1].text,
        'This course introduces the CIA triad and basic cryptography.');
    expect(blocks[3].text,
        'Students should be able to apply security principles.');
  });

  test('list items and week entries start new paragraphs', () {
    final blocks = buildSyllabusBlocks([
      body('Course topics:'),
      body('1. Introduction to security'),
      body('2. Cryptography basics and'),
      body('key exchange'),
      body('• Lab activities'),
      body('Week 3 Network defense'),
    ]);
    expect(blocks.map((b) => b.text), [
      'Course topics:',
      '1. Introduction to security',
      '2. Cryptography basics and key exchange',
      '• Lab activities',
      'Week 3 Network defense',
    ]);
  });

  test('hyphenated line breaks are mended', () {
    final blocks = buildSyllabusBlocks([
      body('Students learn infor-'),
      body('mation security.'),
    ]);
    expect(blocks.single.text, 'Students learn information security.');
  });

  test('a new page starts a new paragraph', () {
    final blocks = buildSyllabusBlocks([
      body('End of page one.', page: 0),
      body('Start of page two.', page: 1),
    ]);
    expect(blocks, hasLength(2));
  });

  test('a wrapped title becomes one heading', () {
    final blocks = buildSyllabusBlocks([
      big('Bachelor of Science in'),
      big('Information Technology'),
      body('Course syllabus for the first semester of the school year,'),
      body('prepared by the BSIT department for all enrolled students.'),
    ]);
    expect(blocks.first.text, 'Bachelor of Science in Information Technology');
    expect(blocks.first.isHeading, isTrue);
  });

  test('a scanned PDF (no text lines) gives no blocks', () {
    expect(buildSyllabusBlocks(const []), isEmpty);
  });

  test('reads the text of a real PDF and finds its headings', () async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Course Syllabus', style: const pw.TextStyle(fontSize: 22)),
          pw.Text('This course covers the CIA triad and basic '
              'cryptography for second year students.'),
          pw.Text('Grading System', style: const pw.TextStyle(fontSize: 18)),
          pw.Text('Quizzes and laboratory work make up the final grade of '
              'every enrolled student.'),
        ],
      ),
    ));

    final lines = extractPdfLines(await doc.save());
    final blocks = buildSyllabusBlocks(lines);

    expect(blocks.where((b) => b.isHeading).map((b) => b.text),
        ['Course Syllabus', 'Grading System']);
    expect(blocks.map((b) => b.text).join(' '), contains('CIA triad'));
  });
}
