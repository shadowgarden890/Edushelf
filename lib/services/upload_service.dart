import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../models/syllabus_content.dart';
import '../models/user_session.dart';
import 'notification_service.dart';
import 'supabase_service.dart';
import 'file_reader.dart' as reader;

class UploadService {
  // ================================================
  // PICK A PDF FILE
  // ================================================
  static Future<PlatformFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  // ================================================
  // FORMAT FILE SIZE
  // ================================================
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ================================================
  // CHECK IF FILE IS PDF
  // ================================================
  static bool isPdf(PlatformFile file) {
    return file.name.toLowerCase().endsWith('.pdf');
  }

  // ================================================
  // SUBMIT SYLLABUS (content, no file)
  // ================================================
  /// Saves a syllabus entered as content and sends it to the admin for
  /// approval, like any material. Returns an error message, or null.
  static Future<String?> submitSyllabus({
    required UserSession session,
    required String title,
    required String code,
    required SyllabusContent content,
  }) async {
    try {
      await SupabaseService.client.from(SupabaseService.materialsTable).insert({
        'title': title.trim(),
        'code': code.trim(),
        'program': session.department,
        'year': 'All Years',
        'term': 'All Terms',
        'instructor': session.fullName,
        'type': 'syllabus',
        'status': 'pending',
        'uploaded_by': session.idNumber,
        'content': content.toJson(),
      });
      await NotificationService.notifyAdmins(
        from: session.idNumber,
        title: 'New Syllabus to Review',
        body: '${session.fullName} submitted the syllabus "${title.trim()}" '
            '(${content.courseCount} courses) for ${session.department}.',
        type: 'admin_material',
      );
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('content')) {
        return 'Syllabus content is not set up on the server yet.';
      }
      return 'Could not submit the syllabus: $msg';
    }
  }

  // ================================================
  // CHECK FILE CREDENTIALS (before upload)
  // ================================================
  /// Largest PDF accepted (Supabase's default per-file storage limit).
  static const maxFileBytes = 50 * 1024 * 1024;

  /// Subject codes like "ITP411", "IT 201", "ACC-101", "ITE322".
  static final _codePattern = RegExp(r'^[A-Za-z]{2,6}[\s-]?\d{2,4}[A-Za-z]?$');

  /// Problems to fix before uploading; empty when everything is correct.
  static List<String> checkCredentials({
    required PlatformFile? file,
    required String title,
    required String code,
  }) {
    final problems = <String>[];
    if (file == null) {
      problems.add('Attach a PDF file.');
    } else {
      if (!isPdf(file)) problems.add('The file must be a PDF (.pdf).');
      if (file.size == 0) problems.add('The file is empty.');
      if (file.size > maxFileBytes) {
        problems.add('The file is ${formatFileSize(file.size)}; the limit is '
            '${formatFileSize(maxFileBytes)}.');
      }
    }
    final t = title.trim();
    if (t.isEmpty) {
      problems.add('Enter the material title.');
    } else if (t.length > 150) {
      problems.add('The title is too long (max 150 characters).');
    }
    final c = code.trim();
    if (c.isEmpty) {
      problems.add('Enter the subject code.');
    } else if (!_codePattern.hasMatch(c)) {
      problems.add('The subject code "$c" should look like IT 201 or ITP411.');
    }
    return problems;
  }

  /// Real PDFs start with "%PDF" (renamed files don't).
  static bool looksLikePdf(Uint8List bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;

  // ================================================
  // SUBMIT MATERIAL
  // ================================================
  static Future<Map<String, dynamic>> submitMaterial({
    required UserSession session,
    required String title,
    required String code,
    required String year,
    required String term,
    required String type,
    required PlatformFile file,
  }) async {
    try {
      // 1. Get file bytes
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await reader.readFileBytes(file.path!);
      }

      if (bytes == null) {
        return {'success': false, 'message': 'Could not read file bytes.'};
      }
      if (!looksLikePdf(bytes)) {
        return {
          'success': false,
          'message':
              'This file is not a valid PDF. Please choose another file.',
        };
      }

      // 2. Build a unique file name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final fileName = '${session.idNumber}_${timestamp}_$safeName';
      final folder = session.department;

      // 3. Upload to Supabase Storage
      final fileUrl = await SupabaseService.uploadFile(
        fileBytes: bytes,
        fileName: fileName,
        folder: folder,
      );

      // 4. Insert metadata into materials table
      await SupabaseService.client.from(SupabaseService.materialsTable).insert({
        'title': title,
        'code': code,
        'program': session.department,
        'year': year,
        'term': term,
        'instructor': session.fullName,
        'type': type,
        'status': 'pending',
        'uploaded_by': session.idNumber,
        'file_url': fileUrl,
        'file_name': file.name,
        'file_size': file.size,
      });

      await NotificationService.notifyAdmins(
        from: session.idNumber,
        title: 'New Material to Review',
        body: '${session.fullName} uploaded "$title" ($code) for '
            '${session.department}.',
        type: 'admin_material',
      );

      return {
        'success': true,
        'message': 'Material submitted successfully!',
        'fileUrl': fileUrl,
      };
    } catch (e) {
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }
}
