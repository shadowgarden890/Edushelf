import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/notification_service.dart';

class TeacherNotificationsScreen extends StatefulWidget {
  final UserSession session;

  /// Shown when there are no notifications yet.
  final String emptyHint;

  const TeacherNotificationsScreen({
    super.key,
    required this.session,
    this.emptyHint =
        "You'll see updates here when the admin reviews your uploads.",
  });

  @override
  State<TeacherNotificationsScreen> createState() =>
      _TeacherNotificationsScreenState();
}

class _TeacherNotificationsScreenState
    extends State<TeacherNotificationsScreen> {
  late final Stream<List<Map<String, dynamic>>> _notifStream;

  /// Cleared notifications, hidden right away: a filtered live stream
  /// doesn't hear about deleted rows.
  final Set<String> _cleared = {};

  @override
  void initState() {
    super.initState();
    // Cache the stream once so it doesn't rebuild on every tab switch
    _notifStream =
        NotificationService.getUserNotifications(widget.session.idNumber);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _notifStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF818CF8)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 50, color: Color(0xFFEF4444)),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load notifications.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        final notifications = (snapshot.data ?? [])
            .where((n) => !_cleared.contains(n['id']?.toString()))
            .toList();

        if (notifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded,
                    size: 60, color: Color(0xFF64748B)),
                const SizedBox(height: 16),
                const Text(
                  'No notifications yet.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.emptyHint,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: notifications.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeader(notifications);
            final data = notifications[index - 1];
            final id = data['id']?.toString() ?? '';
            return Dismissible(
              key: ValueKey('notif-$id'),
              onDismissed: (_) => _clearOne(id),
              background: _swipeBackground(Alignment.centerLeft),
              secondaryBackground: _swipeBackground(Alignment.centerRight),
              child: _buildNotificationCard(data),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(List<Map<String, dynamic>> notifications) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${notifications.length} notification'
              '${notifications.length == 1 ? '' : 's'} • swipe one to clear it',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: () => _clearAll(notifications),
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  Widget _swipeBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
    );
  }

  Future<void> _clearOne(String id) async {
    setState(() => _cleared.add(id));
    try {
      await NotificationService.deleteNotification(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cleared.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not clear it. Check your connection.')));
    }
  }

  Future<void> _clearAll(List<Map<String, dynamic>> notifications) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('Clear all notifications?',
            style: TextStyle(color: Colors.white)),
        content: const Text('They will be removed from this list for good.',
            style: TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final ids = notifications.map((n) => n['id']?.toString() ?? '').toSet();
    setState(() => _cleared.addAll(ids));
    try {
      await NotificationService.clearAll(widget.session.idNumber);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cleared.removeAll(ids));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not clear them. Check your connection.')));
    }
  }

  Widget _buildNotificationCard(Map<String, dynamic> data) {
    final docId = data['id']?.toString() ?? '';
    final type = data['type'] ?? 'info';
    final isRead = data['is_read'] ?? false;
    final title = data['title'] ?? '';
    final body = data['body'] ?? '';

    Color color;
    IconData icon;
    switch (type) {
      case 'approved':
      case 'permission_approved':
        color = const Color(0xFF22C55E);
        icon = Icons.check_circle_rounded;
        break;
      case 'rejected':
      case 'permission_denied':
        color = const Color(0xFFEF4444);
        icon = Icons.cancel_rounded;
        break;
      case 'admin_material':
      case 'admin_permission':
      case 'admin_password':
        color = const Color(0xFFFBBF24);
        icon = Icons.inbox_rounded;
        break;
      case 'student_material':
        color = const Color(0xFF38BDF8);
        icon = Icons.fiber_new_rounded;
        break;
      case 'faculty_activity':
        color = const Color(0xFF818CF8);
        icon = Icons.person_search_rounded;
        break;
      case 'permission_revision':
        color = const Color(0xFFF97316);
        icon = Icons.edit_note_rounded;
        break;
      default:
        color = const Color(0xFF38BDF8);
        icon = Icons.info_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            if (!isRead && docId.isNotEmpty) {
              await NotificationService.markAsRead(docId);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight:
                                    isRead ? FontWeight.w500 : FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF38BDF8),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
