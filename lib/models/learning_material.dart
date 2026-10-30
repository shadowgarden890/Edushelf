import 'package:flutter/material.dart';

import 'syllabus_content.dart';

class LearningMaterial {
  final String id;
  final String code;
  final String title;
  final String program;
  final String year;
  final String term;
  final String instructor;

  /// 0 until the PDF has been opened once and its page count is known.
  int totalPages;

  /// The last page the student was on (for "Resume").
  int currentPage;

  /// Pages the student has actually opened. Progress counts these, so
  /// skipping ahead doesn't mark the pages in between as read.
  final Set<int> readPages;
  final List<Color> coverGradient;
  final String description;
  final bool isSyllabus;
  final String? fileUrl; // public URL from Supabase Storage

  /// ID number of the faculty member who uploaded it.
  final String? uploadedBy;

  /// A syllabus entered as content (courses by semester) instead of a file.
  final SyllabusContent? syllabusContent;

  LearningMaterial({
    required this.id,
    required this.code,
    required this.title,
    required this.program,
    required this.year,
    required this.term,
    required this.instructor,
    required this.totalPages,
    required this.currentPage,
    required this.coverGradient,
    required this.description,
    this.isSyllabus = false,
    this.fileUrl,
    this.uploadedBy,
    this.syllabusContent,
    Set<int>? readPages,
  }) : readPages = readPages ?? <int>{};

  double get progress => totalPages == 0
      ? 0.0
      : (readPages.where((p) => p <= totalPages).length / totalPages)
          .clamp(0.0, 1.0);

  int get progressPercent => (progress * 100).toInt();

  /// True if this material has a PDF attached.
  bool get hasFile => fileUrl != null && fileUrl!.isNotEmpty;

  /// True if this material can be downloaded by students.
  bool get isDownloadable => hasFile;

  /// Build from a row of the Supabase `materials` table.
  factory LearningMaterial.fromRow(Map<String, dynamic> row) {
    final program = row['program'] ?? '';
    return LearningMaterial(
      id: row['id']?.toString() ?? '',
      code: row['code'] ?? '',
      title: row['title'] ?? '',
      program: program,
      year: row['year'] ?? '',
      term: row['term'] ?? '',
      instructor: row['instructor'] ?? '',
      totalPages: 0,
      currentPage: 0,
      coverGradient: gradientForProgram(program),
      description: 'Uploaded by ${row['instructor'] ?? 'faculty'}',
      isSyllabus: row['type'] == 'syllabus',
      fileUrl: row['file_url'],
      uploadedBy: row['uploaded_by'] as String?,
      syllabusContent: row['content'] is Map<String, dynamic>
          ? SyllabusContent.fromJson(row['content'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Serialized form kept in the student's local library (works offline).
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'title': title,
        'program': program,
        'year': year,
        'term': term,
        'instructor': instructor,
        'totalPages': totalPages,
        'currentPage': currentPage,
        'readPages': readPages.toList()..sort(),
        'description': description,
        'isSyllabus': isSyllabus,
        'fileUrl': fileUrl,
        'uploadedBy': uploadedBy,
        'content': syllabusContent?.toJson(),
      };

  factory LearningMaterial.fromJson(Map<String, dynamic> json) {
    final program = json['program'] as String? ?? '';
    return LearningMaterial(
      id: json['id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      program: program,
      year: json['year'] as String? ?? '',
      term: json['term'] as String? ?? '',
      instructor: json['instructor'] as String? ?? '',
      totalPages: json['totalPages'] as int? ?? 0,
      currentPage: json['currentPage'] as int? ?? 0,
      readPages: (json['readPages'] as List? ?? []).cast<int>().toSet(),
      coverGradient: gradientForProgram(program),
      description: json['description'] as String? ?? '',
      isSyllabus: json['isSyllabus'] as bool? ?? false,
      fileUrl: json['fileUrl'] as String?,
      uploadedBy: json['uploadedBy'] as String?,
      syllabusContent: json['content'] is Map<String, dynamic>
          ? SyllabusContent.fromJson(json['content'] as Map<String, dynamic>)
          : null,
    );
  }

  static List<Color> gradientForProgram(String program) {
    switch (program) {
      case 'BSIT':
        return const [Color(0xFF0284C7), Color(0xFF38BDF8)];
      case 'BSBA':
        return const [Color(0xFFD97706), Color(0xFFF59E0B)];
      case 'BSA':
        return const [Color(0xFF059669), Color(0xFF10B981)];
      case 'BSOA':
        return const [Color(0xFFE11D48), Color(0xFFF43F5E)];
      default:
        return const [Color(0xFF3A86FF), Color(0xFF00B4D8)];
    }
  }
}
