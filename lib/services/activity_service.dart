import 'supabase_service.dart';

class ActivityService {
  // ================================================
  // LOG ACTIVITY (student action)
  // ================================================
  /// Logs a student's reading activity.
  /// Called when a student opens a material or bookmarks a page.
  static Future<void> logActivity({
    required String studentId,
    required String studentName,
    required String department,
    required String materialTitle,
    required String materialCode,
    required int currentPage,
    required int totalPages,
    required String
        action, // open | read | progress | bookmark | unbookmark | download
  }) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.activityLogsTable)
          .insert({
        'student_id': studentId,
        'student_name': studentName,
        'department': department,
        'material_title': materialTitle,
        'material_code': materialCode,
        'current_page': currentPage,
        'total_pages': totalPages,
        'action': action,
      });
    } catch (_) {
      // Silently ignore — logging should never break the reader
    }
  }

  // ================================================
  // STREAM — ACTIVITY BY DEPARTMENT (faculty view)
  // ================================================
  /// Real-time stream of all activity in a department.
  static Stream<List<Map<String, dynamic>>> getDepartmentActivity(
      String department) {
    return SupabaseService.client
        .from(SupabaseService.activityLogsTable)
        .stream(primaryKey: ['id'])
        .eq('department', department)
        .order('created_at', ascending: false)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  // ================================================
  // STREAM — ALL ACTIVITY (admin view)
  // ================================================
  /// Real-time stream of the most recent activity in every department.
  static Stream<List<Map<String, dynamic>>> getAllActivity({int limit = 1000}) {
    return SupabaseService.client
        .from(SupabaseService.activityLogsTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  // ================================================
  // STREAM — ACTIVITY BY STUDENT
  // ================================================
  /// Real-time stream of one student's activity.
  static Stream<List<Map<String, dynamic>>> getStudentActivity(
      String studentId) {
    return SupabaseService.client
        .from(SupabaseService.activityLogsTable)
        .stream(primaryKey: ['id'])
        .eq('student_id', studentId)
        .order('created_at', ascending: false)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  // ================================================
  // FETCH — ONE-SHOT (for non-stream usage)
  // ================================================
  static Future<List<Map<String, dynamic>>> fetchDepartmentActivity(
      String department) async {
    final rows = await SupabaseService.client
        .from(SupabaseService.activityLogsTable)
        .select()
        .eq('department', department)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }
}
