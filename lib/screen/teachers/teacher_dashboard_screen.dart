import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/supabase_service.dart';
import '../../widgets/teacher_stat_card.dart';

class TeacherDashboardScreen extends StatelessWidget {
  final UserSession session;

  const TeacherDashboardScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client
          .from(SupabaseService.materialsTable)
          .stream(primaryKey: ['id'])
          .eq('uploaded_by', session.idNumber)
          .order('uploaded_at', ascending: false)
          .map((rows) => rows.cast<Map<String, dynamic>>()),
      builder: (context, snapshot) {
        final docs = snapshot.data ?? [];

        int total = docs.length;
        int pending = 0;
        int approved = 0;
        int rejected = 0;

        for (final data in docs) {
          final status = data['status'] ?? 'pending';
          if (status == 'pending') pending++;
          if (status == 'approved') approved++;
          if (status == 'rejected') rejected++;
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Welcome banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A86FF), Color(0xFF818CF8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3A86FF).withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome to',
                            style:
                                TextStyle(fontSize: 14, color: Colors.white70)),
                        SizedBox(height: 4),
                        Text('Edushelf!',
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1)),
                        SizedBox(height: 8),
                        Text('Upload and manage your learning materials.',
                            style:
                                TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.auto_stories_rounded,
                        size: 42, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            const Text('Your Module Overview',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 14),

            TeacherStatCard(
              label: 'Uploaded Modules',
              value: '$total',
              accentColor: const Color(0xFF38BDF8),
            ),
            const SizedBox(height: 12),
            TeacherStatCard(
              label: 'Pending Review',
              value: '$pending',
              accentColor: const Color(0xFFFBBF24),
            ),
            const SizedBox(height: 12),
            TeacherStatCard(
              label: 'Approved',
              value: '$approved',
              accentColor: const Color(0xFF10B981),
            ),
            const SizedBox(height: 12),
            TeacherStatCard(
              label: 'Returned for Revision',
              value: '$rejected',
              accentColor: const Color(0xFFEF4444),
            ),
            const SizedBox(height: 24),

            const Text('Recent Activity',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 14),

            if (docs.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2541),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text(
                    'No uploads yet.',
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              )
            else
              ...docs.take(3).map((data) => _buildActivityTile(data)),
          ],
        );
      },
    );
  }

  Widget _buildActivityTile(Map<String, dynamic> data) {
    final status = data['status'] ?? 'pending';
    final title = data['title'] ?? 'Untitled';
    final code = data['code'] ?? '';

    Color color;
    IconData icon;
    String subtitle;

    switch (status) {
      case 'approved':
        color = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
        subtitle = 'Approved by administrator';
        break;
      case 'rejected':
        color = const Color(0xFFEF4444);
        icon = Icons.error_outline_rounded;
        final notes = (data['revision_notes'] as String? ?? '').trim();
        subtitle = notes.isEmpty
            ? 'Returned for revision'
            : 'Returned for revision: $notes';
        break;
      default:
        color = const Color(0xFF38BDF8);
        icon = Icons.cloud_done_rounded;
        subtitle = 'Pending review';
    }

    final time = _timeAgo(data['uploaded_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$code — $title',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: status == 'rejected'
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF94A3B8),
                        fontSize: 12)),
              ],
            ),
          ),
          Text(time,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ],
      ),
    );
  }

  String _timeAgo(dynamic uploadedAt) {
    if (uploadedAt == null) return '';
    DateTime time;
    try {
      time = DateTime.parse(uploadedAt.toString());
    } catch (_) {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
