import '../services/syllabus_text.dart';

/// One course row: code, title, units.
class SyllabusCourse {
  SyllabusCourse(
      {required this.code, required this.title, required this.units});

  String code;
  String title;
  double units;

  Map<String, dynamic> toJson() =>
      {'code': code, 'title': title, 'units': units};

  factory SyllabusCourse.fromJson(Map<String, dynamic> json) => SyllabusCourse(
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        units: (json['units'] as num?)?.toDouble() ?? 0,
      );
}

/// A year / semester with its courses, e.g. "First Year - First Semester".
class SyllabusSection {
  SyllabusSection({required this.title, List<SyllabusCourse>? courses})
      : courses = courses ?? [];

  String title;
  final List<SyllabusCourse> courses;

  double get totalUnits => courses.fold(0, (sum, c) => sum + c.units);

  Map<String, dynamic> toJson() => {
        'title': title,
        'courses': [for (final c in courses) c.toJson()],
      };

  factory SyllabusSection.fromJson(Map<String, dynamic> json) =>
      SyllabusSection(
        title: json['title'] as String? ?? '',
        courses: [
          for (final c in (json['courses'] as List? ?? []))
            SyllabusCourse.fromJson(c as Map<String, dynamic>),
        ],
      );
}

/// A syllabus / curriculum outline entered as content (not a PDF file).
/// Saved as JSON in materials.content.
class SyllabusContent {
  SyllabusContent({
    this.programTitle = '',
    this.notes = '',
    List<SyllabusSection>? sections,
  }) : sections = sections ?? [];

  String programTitle;
  String notes;
  final List<SyllabusSection> sections;

  double get totalUnits => sections.fold(0, (sum, s) => sum + s.totalUnits);
  int get courseCount => sections.fold(0, (sum, s) => sum + s.courses.length);

  Map<String, dynamic> toJson() => {
        'programTitle': programTitle,
        'notes': notes,
        'sections': [for (final s in sections) s.toJson()],
      };

  factory SyllabusContent.fromJson(Map<String, dynamic> json) =>
      SyllabusContent(
        programTitle: json['programTitle'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        sections: [
          for (final s in (json['sections'] as List? ?? []))
            SyllabusSection.fromJson(s as Map<String, dynamic>),
        ],
      );

  /// Reads a curriculum outline PDF (year/semester tables of
  /// Code / Course Title / Units) into editable content.
  factory SyllabusContent.fromPdfLines(List<PdfLine> lines) {
    final content = SyllabusContent();
    final notes = <String>[];
    var titleSize = 0.0;
    var lastWasTitle = false;
    SyllabusSection? section;
    var pending = ''; // a course row broken over two lines

    for (final line in lines) {
      final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty || _footer.hasMatch(text)) continue;

      if (_isTermHeading(text)) {
        section = SyllabusSection(title: text);
        content.sections.add(section);
        pending = '';
        continue;
      }

      if (section == null) {
        // Before the first table: the program title and notes.
        final sameSize = (line.fontSize - titleSize).abs() < 0.5;
        if (line.bold && lastWasTitle && sameSize) {
          // The title wraps onto a second line.
          content.programTitle = '${content.programTitle} $text';
        } else if (line.bold &&
            line.fontSize > titleSize &&
            text.length <= 120) {
          if (content.programTitle.isNotEmpty) {
            notes.insert(0, content.programTitle);
          }
          content.programTitle = text;
          titleSize = line.fontSize;
          lastWasTitle = true;
        } else {
          notes.add(text);
          lastWasTitle = false;
        }
        continue;
      }

      if (_headerRow.hasMatch(text) || _totalRow.hasMatch(text)) {
        pending = '';
        continue;
      }

      final candidate = pending.isEmpty ? text : '$pending $text';
      final match = _courseRow.firstMatch(candidate);
      if (match != null) {
        section.courses.add(SyllabusCourse(
          code: match.group(1)!.trim(),
          title: match.group(2)!.trim(),
          units: double.parse(match.group(3)!),
        ));
        pending = '';
      } else if (_codeStart.hasMatch(candidate) && pending.isEmpty) {
        pending = candidate; // wait for the rest of the row
      } else {
        pending = '';
      }
    }

    content.notes = _joinParagraphs(notes);
    return content;
  }
}

/// "First Year - First Semester", "Third Year - Midyear Term", "Summer".
bool _isTermHeading(String text) {
  if (text.length > 60) return false;
  final t = text.toLowerCase();
  final hasYear = RegExp(
          r'\b(first|second|third|fourth|fifth|1st|2nd|3rd|4th|5th)\s+year\b')
      .hasMatch(t);
  final hasTerm =
      RegExp(r'\b(semester|sem|term|midyear|mid-year|summer|trimester)\b')
          .hasMatch(t);
  return (hasYear && hasTerm) ||
      RegExp(r'^(summer|midyear)( term)?$').hasMatch(t);
}

final _headerRow =
    RegExp(r'^code\s+(course\s+)?(title|description)', caseSensitive: false);
final _totalRow = RegExp(r'^total\b', caseSensitive: false);
final _footer = RegExp(r'\bpage \d+$', caseSensitive: false);

/// Codes like "IT 111", "GEd 102", "PATHFit 1", "GE 1", "ACCTG 101".
final _codeStart = RegExp(r'^[A-Za-z]{1,10}\s?\d{1,3}[A-Za-z]?\b');
final _courseRow = RegExp(
    r'^([A-Za-z]{1,10}\s?\d{1,3}[A-Za-z]?)\s+(.+?)\s+(\d{1,2}(?:\.\d)?)$');

String _joinParagraphs(List<String> lines) {
  final out = StringBuffer();
  for (final l in lines) {
    if (out.isEmpty) {
      out.write(l);
    } else if (out.toString().endsWith('.') || out.toString().endsWith(':')) {
      out.write('\n$l');
    } else {
      out.write(' $l');
    }
  }
  return out.toString();
}

/// "3" instead of "3.0", "1.5" stays.
String formatUnits(double units) => units == units.roundToDouble()
    ? units.toInt().toString()
    : units.toString();
