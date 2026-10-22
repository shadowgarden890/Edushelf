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
  int currentPage;
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
  });

  double get progress =>
      totalPages == 0 ? 0.0 : (currentPage / totalPages).clamp(0.0, 1.0);

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

// ================================================
// DEMO DATA — Used as fallback when Supabase is empty.
// You can remove this list later if you want.
// ================================================
List<LearningMaterial> appMaterials = [
  // BSIT
  LearningMaterial(
    id: 'demo_it_201',
    code: 'IT 201',
    title: 'Data Structures & Algorithms in Java',
    program: 'BSIT',
    year: '2nd Year',
    term: '1st Sem',
    instructor: 'Prof. E. Cruz, MSCS',
    totalPages: 30,
    currentPage: 0,
    coverGradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
    description:
        'Comprehensive guide covering Stacks, Queues, Linked Lists, Trees, Graphs, and Sorting algorithms.',
  ),
  LearningMaterial(
    id: 'demo_it_305',
    code: 'IT 305',
    title: 'Information Assurance & Cybersecurity',
    program: 'BSIT',
    year: '3rd Year',
    term: '2nd Sem',
    instructor: 'Prof. N. Ramos, MIT',
    totalPages: 28,
    currentPage: 0,
    coverGradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    description:
        'Principles of CIA Triad, Cryptography, Network Defense, and Incident Response.',
    isSyllabus: true,
  ),
  LearningMaterial(
    id: 'demo_it_102',
    code: 'IT 102',
    title: 'Computer Programming 1 (Python & Logic)',
    program: 'BSIT',
    year: '1st Year',
    term: '1st Sem',
    instructor: 'Engr. D. Lim, MIT',
    totalPages: 20,
    currentPage: 0,
    coverGradient: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
    description:
        'Introduction to algorithmic thinking, flowcharts, control structures, and functions.',
  ),

  // BSA
  LearningMaterial(
    id: 'demo_acc_101',
    code: 'ACC 101',
    title: 'Conceptual Framework & Accounting Standards',
    program: 'BSA',
    year: '1st Year',
    term: '1st Sem',
    instructor: 'Prof. A. Mendoza, CPA',
    totalPages: 24,
    currentPage: 0,
    coverGradient: const [Color(0xFF059669), Color(0xFF10B981)],
    description:
        'Fundamental principles of Philippine Financial Reporting Standards (PFRS).',
  ),
  LearningMaterial(
    id: 'demo_tax_301',
    code: 'TAX 301',
    title: 'Income Taxation & TRAIN/EOPT Law Updates',
    program: 'BSA',
    year: '3rd Year',
    term: '2nd Sem',
    instructor: 'Atty. R. Bautista, CPA',
    totalPages: 40,
    currentPage: 0,
    coverGradient: const [Color(0xFF0D9488), Color(0xFF115E59)],
    description: 'Comprehensive guide on Individual & Corporate Income Tax.',
    isSyllabus: true,
  ),

  // BSBA
  LearningMaterial(
    id: 'demo_mktg_101',
    code: 'MKTG 101',
    title: 'Principles of Marketing Management',
    program: 'BSBA',
    year: '1st Year',
    term: '1st Sem',
    instructor: 'Prof. L. Garcia, MBA',
    totalPages: 26,
    currentPage: 0,
    coverGradient: const [Color(0xFFD97706), Color(0xFFF59E0B)],
    description:
        'Marketing mix (4Ps), market segmentation, and consumer behavior.',
  ),
  LearningMaterial(
    id: 'demo_ba_402',
    code: 'BA 402',
    title: 'Strategic Management & Corporate Policy',
    program: 'BSBA',
    year: '4th Year',
    term: '1st Sem',
    instructor: 'Prof. K. Villanueva, MBA',
    totalPages: 34,
    currentPage: 0,
    coverGradient: const [Color(0xFFB45309), Color(0xFF92400E)],
    description:
        'SWOT analysis, Michael Porter Five Forces, and competitive strategy.',
    isSyllabus: true,
  ),

  // BSOA
  LearningMaterial(
    id: 'demo_oa_101',
    code: 'OA 101',
    title: 'Keyboarding & Document Processing',
    program: 'BSOA',
    year: '1st Year',
    term: '1st Sem',
    instructor: 'Prof. G. Dizon, MSOA',
    totalPages: 22,
    currentPage: 0,
    coverGradient: const [Color(0xFFE11D48), Color(0xFFF43F5E)],
    description: 'Touch keyboarding techniques and business letter formatting.',
  ),
  LearningMaterial(
    id: 'demo_oa_302',
    code: 'OA 302',
    title: 'Advanced Records Management & Electronic Filing',
    program: 'BSOA',
    year: '3rd Year',
    term: '2nd Sem',
    instructor: 'Prof. H. Morales, MSOA',
    totalPages: 32,
    currentPage: 0,
    coverGradient: const [Color(0xFFBE123C), Color(0xFF9F1239)],
    description:
        'Rules of alphabetic indexing, numeric filing, and document preservation.',
    isSyllabus: true,
  ),
];
