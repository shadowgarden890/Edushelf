import 'package:flutter/material.dart';

import '../../models/department.dart';
import '../../services/activity_service.dart';
import '../teachers/teacher_activity_logs_screen.dart';

const _card = Color(0xFF1C2541);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFFFBBF24);

/// Everything students do with materials: a live feed of recent events,
/// or grouped per student (progress, bookmarks, accessed materials).
/// With [department] it shows only that department.
class AdminActivityScreen extends StatefulWidget {
  const AdminActivityScreen(
      {super.key, this.department, this.embedded = false});

  /// 'BSIT', 'BSA', ... or null for every department.
  final String? department;

  /// True inside the admin dashboard (no app bar of its own).
  final bool embedded;

  @override
  State<AdminActivityScreen> createState() => _AdminActivityScreenState();
}

class _AdminActivityScreenState extends State<AdminActivityScreen> {
  late final _stream = ActivityService.getAllActivity();
  late String? _department = widget.department;
  String _view = 'recent';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        if (snapshot.hasError) {
          return _message(Icons.cloud_off_rounded,
              'Could not load activity. Check your connection.');
        }

        final q = _search.trim().toLowerCase();
        final logs = (snapshot.data ?? []).where((r) {
          if (_department != null && r['department'] != _department) {
            return false;
          }
          if (q.isEmpty) return true;
          return '${r['student_name']} ${r['student_id']} '
                  '${r['material_title']} ${r['material_code']}'
              .toLowerCase()
              .contains(q);
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildFilters(),
            const SizedBox(height: 14),
            if (logs.isEmpty)
              _message(
                  Icons.history_toggle_off_rounded,
                  'No activity yet. It appears here as students open, read, '
                  'bookmark and download materials.')
            else if (_view == 'recent')
              ...logs.take(200).map(_eventTile)
            else
              ...StudentActivity.group(logs).map(_studentTile),
          ],
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
            widget.department == null
                ? 'Activity Logs'
                : '${widget.department} Activity',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: body,
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                foregroundColor: _muted,
                selectedForegroundColor: Colors.black,
                selectedBackgroundColor: _accent,
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              segments: const [
                ButtonSegment(
                    value: 'recent',
                    icon: Icon(Icons.bolt_rounded, size: 16),
                    label: Text('Recent')),
                ButtonSegment(
                    value: 'students',
                    icon: Icon(Icons.groups_rounded, size: 16),
                    label: Text('By student')),
              ],
              selected: {_view},
              onSelectionChanged: (v) => setState(() => _view = v.first),
            ),
            if (widget.department == null)
              for (final code in [null, ...Department.all.map((d) => d.code)])
                ChoiceChip(
                  label: Text(code ?? 'All'),
                  selected: _department == code,
                  onSelected: (_) => setState(() => _department = code),
                  selectedColor: _accent,
                  backgroundColor: _card,
                  labelStyle: TextStyle(
                      color: _department == code ? Colors.black : _muted,
                      fontWeight: FontWeight.w600),
                  side: const BorderSide(color: Color(0xFF334155)),
                  showCheckmark: false,
                ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _search = v),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search student, ID or material...',
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            prefixIcon: const Icon(Icons.search, color: _muted),
            filled: true,
            fillColor: _card,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _eventTile(Map<String, dynamic> r) {
    final (icon, color, verb) = switch (r['action']) {
      'open' => (Icons.menu_book_rounded, const Color(0xFF38BDF8), 'Opened'),
      'read' => (
          Icons.auto_stories_rounded,
          const Color(0xFF818CF8),
          'Reading'
        ),
      'progress' => (Icons.flag_rounded, const Color(0xFF22C55E), 'Stopped at'),
      'bookmark' => (Icons.bookmark_rounded, _accent, 'Bookmarked'),
      'unbookmark' => (
          Icons.bookmark_remove_rounded,
          const Color(0xFF64748B),
          'Removed bookmark in'
        ),
      'download' => (
          Icons.download_rounded,
          const Color(0xFF10B981),
          'Downloaded'
        ),
      _ => (Icons.circle_outlined, _muted, 'Used'),
    };
    final page = (r['current_page'] as num?)?.toInt() ?? 0;
    final total = (r['total_pages'] as num?)?.toInt() ?? 0;
    final where =
        page > 0 ? ' • page $page${total > 0 ? ' of $total' : ''}' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${r['student_name'] ?? 'A student'} ',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(
                        text: '${verb.toLowerCase()} ',
                        style: const TextStyle(color: _muted)),
                    TextSpan(text: '${r['material_code'] ?? ''}'),
                  ]),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text('${r['material_title'] ?? ''}$where',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(timeAgo(r['created_at']),
                  style:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              if (widget.department == null)
                Text('${r['department'] ?? ''}',
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studentTile(StudentActivity s) {
    final bookmarks =
        s.materials.fold<int>(0, (n, m) => n + m.bookmarks.length);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.15),
            child: Text(s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
          ),
          title: Text(s.name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(
              '${s.studentId} • ${s.materials.length} material'
              '${s.materials.length == 1 ? '' : 's'} • $bookmarks bookmark'
              '${bookmarks == 1 ? '' : 's'}',
              style: const TextStyle(color: _muted, fontSize: 12)),
          trailing: Text(
              s.lastActive == null
                  ? ''
                  : timeAgo(s.lastActive!.toIso8601String()),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => StudentActivityScreen(student: s)),
          ),
        ),
      ),
    );
  }

  Widget _message(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF64748B), size: 44),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted)),
          ],
        ),
      );
}

/// "just now", "5m ago", "3h ago", "2d ago" or the date.
String timeAgo(Object? isoTime) {
  final t = DateTime.tryParse(isoTime as String? ?? '')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.month}/${t.day}/${t.year}';
}
