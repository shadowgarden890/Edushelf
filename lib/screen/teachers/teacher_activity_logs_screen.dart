import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/activity_service.dart';

const _card = Color(0xFF1C2541);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFF38BDF8);

/// Activity Logs: student list -> select student -> reading progress,
/// bookmarked pages and accessed materials.
class TeacherActivityLogsScreen extends StatefulWidget {
  final UserSession session;

  const TeacherActivityLogsScreen({super.key, required this.session});

  @override
  State<TeacherActivityLogsScreen> createState() =>
      _TeacherActivityLogsScreenState();
}

class _TeacherActivityLogsScreenState extends State<TeacherActivityLogsScreen> {
  late final _stream =
      ActivityService.getDepartmentActivity(widget.session.department);
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
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
              child: Text(
                'Could not load activity.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          );
        }

        final students = StudentActivity.group(snapshot.data ?? []);
        if (students.isEmpty) return _buildEmptyState();

        final q = _search.trim().toLowerCase();
        final shown = students
            .where((s) =>
                q.isEmpty ||
                s.name.toLowerCase().contains(q) ||
                s.studentId.toLowerCase().contains(q))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Student Activity',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              '${students.length} student${students.length == 1 ? '' : 's'} '
              'in ${widget.session.department}. Select a student to see '
              'their reading progress, bookmarks and materials.',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 14),
            TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search name or ID number...',
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ...shown.map((s) => _buildStudentCard(context, s)),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 60, color: Color(0xFF64748B)),
          SizedBox(height: 16),
          Text('No activity yet.',
              style: TextStyle(color: _muted, fontSize: 14)),
          SizedBox(height: 6),
          Text('Student reading activity will appear here.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStudentCard(BuildContext context, StudentActivity s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => StudentActivityScreen(student: s)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: _accent.withValues(alpha: 0.15),
                  child: const Icon(Icons.person, color: _accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('ID: ${s.studentId}',
                          style: const TextStyle(color: _muted, fontSize: 12)),
                      const SizedBox(height: 2),
                      Text(
                        '${s.materials.length} material'
                        '${s.materials.length == 1 ? '' : 's'} • '
                        'last active ${_ago(s.lastActive)}',
                        style: const TextStyle(
                            color: _accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: Color(0xFF64748B)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// ONE STUDENT
// =====================================================================
class StudentActivityScreen extends StatelessWidget {
  const StudentActivityScreen({super.key, required this.student});

  final StudentActivity student;

  @override
  Widget build(BuildContext context) {
    final materials = student.materials;
    final bookmarked = materials.where((m) => m.bookmarks.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(student.name,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('ID: ${student.studentId}',
              style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 20),

          // 1. READING PROGRESS
          _sectionTitle(Icons.auto_stories_rounded, 'Reading Progress'),
          if (materials.every((m) => m.lastPage == 0))
            _empty('No pages read yet.')
          else
            ...materials.where((m) => m.lastPage > 0).map(_progressCard),
          const SizedBox(height: 20),

          // 2. BOOKMARKED PAGES
          _sectionTitle(Icons.bookmark_rounded, 'Bookmarked Pages'),
          if (bookmarked.isEmpty)
            _empty('No bookmarks.')
          else
            ...bookmarked.map(_bookmarkCard),
          const SizedBox(height: 20),

          // 3. ACCESSED MATERIALS
          _sectionTitle(Icons.folder_open_rounded, 'Accessed Materials'),
          ...materials.map(_accessCard),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, color: _accent, size: 18),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child:
            Text(text, style: const TextStyle(color: _muted, fontSize: 12.5)),
      );

  Widget _box({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _materialTitle(MaterialActivity m) => Text(
        '${m.code} — ${m.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      );

  Widget _progressCard(MaterialActivity m) {
    final progress = m.progress;
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _materialTitle(m),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF0B132B),
            valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 6),
          Text(
            m.totalPages > 0
                ? 'Page ${m.lastPage} of ${m.totalPages} '
                    '(${(progress * 100).toInt()}%)'
                : 'Page ${m.lastPage}',
            style: const TextStyle(
                color: _accent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _bookmarkCard(MaterialActivity m) {
    final pages = m.bookmarks.toList()..sort();
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _materialTitle(m),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in pages)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Page $p',
                      style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accessCard(MaterialActivity m) {
    return _box(
      child: Row(
        children: [
          Icon(m.downloads > 0 ? Icons.download_done_rounded : Icons.visibility,
              color: m.downloads > 0 ? const Color(0xFF10B981) : _muted,
              size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _materialTitle(m),
                const SizedBox(height: 2),
                Text(
                  [
                    m.opens > 0 ? 'Opened ${m.opens}×' : 'Opened',
                    if (m.downloads > 0) 'downloaded ${m.downloads}×',
                    'last ${_ago(m.lastAccess)}',
                  ].join(' • '),
                  style: const TextStyle(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// SUMMARIES BUILT FROM activity_logs ROWS
// =====================================================================
class StudentActivity {
  StudentActivity(this.studentId, this.name, this.materials, this.lastActive);

  final String studentId;
  final String name;
  final List<MaterialActivity> materials; // most recently accessed first
  final DateTime? lastActive;

  /// Groups log rows (any order) by student, most recently active first.
  static List<StudentActivity> group(List<Map<String, dynamic>> logs) {
    final sorted = [...logs]
      ..sort((a, b) => _time(a).compareTo(_time(b))); // oldest first

    final byStudent = <String, List<Map<String, dynamic>>>{};
    for (final log in sorted) {
      byStudent
          .putIfAbsent(log['student_id'] as String? ?? 'unknown', () => [])
          .add(log);
    }

    final result = byStudent.entries.map((e) {
      final rows = e.value;
      final perMaterial = <String, MaterialActivity>{};
      for (final row in rows) {
        final title = row['material_title'] as String? ?? 'Unknown';
        perMaterial
            .putIfAbsent(
                title,
                () => MaterialActivity(
                    title, row['material_code'] as String? ?? ''))
            .add(row);
      }
      final materials = perMaterial.values.toList()
        ..sort((a, b) => (b.lastAccess ?? DateTime(0))
            .compareTo(a.lastAccess ?? DateTime(0)));
      return StudentActivity(
        e.key,
        rows.last['student_name'] as String? ?? 'Unknown',
        materials,
        materials.isEmpty ? null : materials.first.lastAccess,
      );
    }).toList()
      ..sort((a, b) =>
          (b.lastActive ?? DateTime(0)).compareTo(a.lastActive ?? DateTime(0)));
    return result;
  }

  static DateTime _time(Map<String, dynamic> row) =>
      DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime(0);
}

class MaterialActivity {
  MaterialActivity(this.title, this.code);

  final String title;
  final String code;
  int lastPage = 0;
  int totalPages = 0;
  int opens = 0;
  int downloads = 0;
  DateTime? lastAccess;
  final Set<int> bookmarks = {};

  double get progress =>
      totalPages == 0 ? 0 : (lastPage / totalPages).clamp(0.0, 1.0);

  /// Rows must be fed oldest first so bookmarks replay correctly.
  void add(Map<String, dynamic> row) {
    final page = (row['current_page'] as num?)?.toInt() ?? 0;
    final total = (row['total_pages'] as num?)?.toInt() ?? 0;
    if (total > totalPages) totalPages = total;
    lastAccess = StudentActivity._time(row);

    switch (row['action']) {
      case 'open':
        opens++;
        if (page > 0) lastPage = page;
      case 'read':
      case 'progress':
        if (page > 0) lastPage = page;
      case 'bookmark':
        if (page > 0) bookmarks.add(page);
      case 'unbookmark':
        bookmarks.remove(page);
      case 'download':
        downloads++;
    }
  }
}

String _ago(DateTime? time) {
  if (time == null) return '';
  final d = DateTime.now().difference(time.toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${time.month}/${time.day}/${time.year}';
}
