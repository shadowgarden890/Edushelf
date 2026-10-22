import 'supabase_service.dart';

class NotificationService {
  // ================================================
  // STREAM — USER'S NOTIFICATIONS
  // ================================================
  /// Real-time stream of a user's notifications (newest first).
  static Stream<List<Map<String, dynamic>>> getUserNotifications(
      String userId) {
    return SupabaseService.client
        .from(SupabaseService.notificationsTable)
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  // ================================================
  // STREAM — UNREAD COUNT
  // ================================================
  /// Real-time stream of unread notification count (for badge).
  static Stream<List<Map<String, dynamic>>> getUnreadCount(String userId) {
    // Filtered here, not on the server: a live stream keeps rows that stop
    // matching a server filter, so read notifications would still count.
    return SupabaseService.client
        .from(SupabaseService.notificationsTable)
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .map((rows) => rows
            .cast<Map<String, dynamic>>()
            .where((r) => r['is_read'] != true)
            .toList());
  }

  /// Marks all of a user's notifications as read (when they open the list).
  static Future<void> markAllRead(String userId) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.notificationsTable)
          .update({'is_read': true})
          .eq('recipient_id', userId)
          .eq('is_read', false);
    } catch (_) {
      // Non-critical.
    }
  }

  // ================================================
  // MARK AS READ
  // ================================================
  static Future<void> markAsRead(String notificationId) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.notificationsTable)
          .update({'is_read': true}).eq('id', notificationId);
    } catch (_) {
      // Silently ignore — non-critical
    }
  }

  // ================================================
  // CLEAR
  // ================================================
  /// Removes one notification. Throws if it can't be reached.
  static Future<void> deleteNotification(String notificationId) async {
    await SupabaseService.client
        .from(SupabaseService.notificationsTable)
        .delete()
        .eq('id', notificationId);
  }

  /// Removes all of a user's notifications. Throws if it can't be reached.
  static Future<void> clearAll(String userId) async {
    await SupabaseService.client
        .from(SupabaseService.notificationsTable)
        .delete()
        .eq('recipient_id', userId);
  }

  // ================================================
  // CREATE NOTIFICATION
  // ================================================
  /// Called by admin when approving/rejecting a material.
  static Future<void> createNotification({
    required String to,
    required String from,
    required String title,
    required String body,
    required String type,
  }) async {
    await SupabaseService.client
        .from(SupabaseService.notificationsTable)
        .insert({
      'recipient_id': to,
      'sender_id': from,
      'title': title,
      'body': body,
      'type': type,
      'is_read': false,
    });
  }

  // ================================================
  // SEND TO MANY
  // ================================================
  /// Sends the same notification to several users in one request.
  /// Never throws: a failed alert must not break the action behind it.
  static Future<void> notifyMany({
    required Iterable<String> to,
    required String from,
    required String title,
    required String body,
    required String type,
  }) async {
    final recipients = to.where((id) => id.isNotEmpty && id != from).toSet();
    if (recipients.isEmpty) return;
    try {
      await SupabaseService.client
          .from(SupabaseService.notificationsTable)
          .insert([
        for (final id in recipients)
          {
            'recipient_id': id,
            'sender_id': from,
            'title': title,
            'body': body,
            'type': type,
            'is_read': false,
          }
      ]);
    } catch (_) {}
  }

  /// ID numbers of users with [role] (optionally in one department).
  static Future<List<String>> idsWithRole(String role,
      {String? department}) async {
    try {
      var query = SupabaseService.client
          .from(SupabaseService.usersTable)
          .select('id_number')
          .eq('role', role);
      if (department != null) query = query.eq('department', department);
      final rows = await query;
      return [for (final r in rows) r['id_number'] as String];
    } catch (_) {
      return [];
    }
  }

  /// Alerts every admin (new uploads, permission requests...).
  static Future<void> notifyAdmins({
    required String from,
    required String title,
    required String body,
    required String type,
  }) async =>
      notifyMany(
          to: await idsWithRole('admin'),
          from: from,
          title: title,
          body: body,
          type: type);

  // ================================================
  // GET — ONE-SHOT FETCH (for non-stream usage)
  // ================================================
  static Future<List<Map<String, dynamic>>> fetchUserNotifications(
      String userId) async {
    final rows = await SupabaseService.client
        .from(SupabaseService.notificationsTable)
        .select()
        .eq('recipient_id', userId)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }
}
