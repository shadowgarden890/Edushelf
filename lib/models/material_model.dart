class MaterialModel {
  final String id;
  final String title;
  final String code;
  final String program;
  final String year;
  final String term;
  final String instructor;
  final String type; // 'learning_material' or 'syllabus'
  final String status; // 'pending', 'approved', 'rejected'
  final String uploadedBy;
  final String? fileUrl; // public URL to the PDF in Supabase Storage
  final String? fileName;
  final int? fileSize;

  MaterialModel({
    required this.id,
    required this.title,
    required this.code,
    required this.program,
    required this.year,
    required this.term,
    required this.instructor,
    required this.type,
    required this.status,
    required this.uploadedBy,
    this.fileUrl,
    this.fileName,
    this.fileSize,
  });

  /// Create a MaterialModel from a Supabase row (Map).
  factory MaterialModel.fromMap(Map<String, dynamic> data) {
    return MaterialModel(
      id: data['id']?.toString() ?? '',
      title: data['title'] ?? '',
      code: data['code'] ?? '',
      program: data['program'] ?? '',
      year: data['year'] ?? '',
      term: data['term'] ?? '',
      instructor: data['instructor'] ?? '',
      type: data['type'] ?? 'learning_material',
      status: data['status'] ?? 'pending',
      uploadedBy: data['uploaded_by'] ?? '',
      fileUrl: data['file_url'],
      fileName: data['file_name'],
      fileSize: data['file_size'],
    );
  }

  /// Convert to a Map for Supabase writes.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'code': code,
      'program': program,
      'year': year,
      'term': term,
      'instructor': instructor,
      'type': type,
      'status': status,
      'uploaded_by': uploadedBy,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
    };
  }

  /// True if this is a syllabus (needs permission to download).
  bool get isSyllabus => type == 'syllabus';

  /// True if this has been approved by admin.
  bool get isApproved => status == 'approved';

  /// True if this is still pending review.
  bool get isPending => status == 'pending';

  /// True if this was rejected.
  bool get isRejected => status == 'rejected';

  /// True if a PDF file is attached.
  bool get hasFile => fileUrl != null && fileUrl!.isNotEmpty;
}
