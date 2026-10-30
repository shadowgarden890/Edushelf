import 'package:flutter/material.dart';

import '../../models/department.dart';
import '../../services/supabase_service.dart';
import 'admin_activity_screen.dart';
import 'material_preview.dart';

const _bg = Color(0xFF0B132B);
const _card = Color(0xFF1C2541);
const _muted = Color(0xFF94A3B8);
const _dim = Color(0xFF64748B);

typedef _Row = Map<String, dynamic>;

/// One department's folders: Students, Faculty, Syllabus, Reading
/// Materials (one folder per faculty member who uploaded) and Activity.
class DepartmentScreen extends StatefulWidget {
  const DepartmentScreen(
      {super.key, required this.department, this.users, this.materials});

  final Department department;

  /// Live data from the server unless given (tests pass sample rows).
  final Stream<List<Map<String, dynamic>>>? users;
  final Stream<List<Map<String, dynamic>>>? materials;

  @override
  State<DepartmentScreen> createState() => _DepartmentScreenState();
}

class _DepartmentScreenState extends State<DepartmentScreen> {
  late final _users = widget.users ??
      SupabaseService.client
          .from(SupabaseService.usersTable)
          .stream(primaryKey: ['id']).map((rows) => rows.cast<_Row>());
  late final _materials = widget.materials ??
      SupabaseService.client
          .from(SupabaseService.materialsTable)
          .stream(primaryKey: ['id'])
          .order('uploaded_at', ascending: false)
          .map((rows) => rows.cast<_Row>());

  Department get _dept => widget.department;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_dept.code,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: StreamBuilder<List<_Row>>(
        stream: _users,
        builder: (context, usersSnap) => StreamBuilder<List<_Row>>(
          stream: _materials,
          builder: (context, matsSnap) {
            if (!usersSnap.hasData || !matsSnap.hasData) {
              if (usersSnap.hasError || matsSnap.hasError) {
                return const Center(
                    child: Text('Could not load. Check your connection.',
                        style: TextStyle(color: _muted)));
              }
              return Center(
                  child: CircularProgressIndicator(color: _dept.color));
            }
            return _buildContent(usersSnap.data!, matsSnap.data!);
          },
        ),
      ),
    );
  }

  Widget _buildContent(List<_Row> allUsers, List<_Row> allMaterials) {
    final users = allUsers.where((u) => u['department'] == _dept.code).toList();
    final students = users.where((u) => u['role'] == 'student').toList();
    final faculty = users.where((u) => u['role'] == 'instructor').toList();
    final materials =
        allMaterials.where((m) => m['program'] == _dept.code).toList();
    final syllabi = materials.where((m) => m['type'] == 'syllabus').toList();
    final reading = materials.where((m) => m['type'] != 'syllabus').toList();

    // Names for "uploaded by" folders, from every account.
    final names = {
      for (final u in allUsers)
        if (u['id_number'] != null)
          u['id_number'] as String: u['full_name'] as String? ?? '',
    };

    final folders = [
      _Folder(
          'Students',
          Icons.school_rounded,
          const Color(0xFF38BDF8),
          '${students.length} accounts',
          () => _open(_StudentsFolder(dept: _dept, students: students))),
      _Folder(
          'Faculty',
          Icons.co_present_rounded,
          const Color(0xFF818CF8),
          '${faculty.length} accounts',
          () => _open(_FacultyFolder(
              dept: _dept, faculty: faculty, materials: materials))),
      _Folder(
          'Syllabus',
          Icons.table_chart_rounded,
          const Color(0xFF10B981),
          '${syllabi.length} syllabi',
          () => _open(_MaterialsList(
              title: '${_dept.code} Syllabus',
              materials: syllabi,
              emptyText: 'No syllabus uploaded yet.'))),
      _Folder(
          'Reading Materials',
          Icons.menu_book_rounded,
          const Color(0xFFFBBF24),
          '${reading.length} materials',
          () => _open(
              _UploadersFolder(dept: _dept, materials: reading, names: names))),
      _Folder(
          'Activity Logs',
          Icons.insights_rounded,
          const Color(0xFFF472B6),
          'What students are reading',
          () => _open(AdminActivityScreen(department: _dept.code))),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildHeader(students.length, faculty.length, materials),
            const SizedBox(height: 22),
            const Text('Folders',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GridView(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 150,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: folders.map(_folderCard).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int students, int faculty, List<_Row> materials) {
    final pending = materials.where((m) => m['status'] == 'pending').length;
    final approved = materials.where((m) => m['status'] == 'approved').length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [_dept.color.withValues(alpha: 0.35), _card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _dept.color.withValues(alpha: 0.4)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DepartmentLogo(dept: _dept, size: 96),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_dept.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(Icons.school_rounded, '$students students'),
                  _pill(Icons.co_present_rounded, '$faculty faculty'),
                  _pill(Icons.check_circle_rounded, '$approved approved'),
                  _pill(Icons.hourglass_top_rounded, '$pending pending'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      );

  Widget _folderCard(_Folder f) => Material(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: f.onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_rounded, color: f.color, size: 36),
                    const Spacer(),
                    Icon(f.icon, color: f.color.withValues(alpha: 0.7)),
                  ],
                ),
                const Spacer(),
                Text(f.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 2),
                Text(f.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      );

  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

class _Folder {
  const _Folder(this.title, this.icon, this.color, this.subtitle, this.onTap);
  final String title;
  final IconData icon;
  final Color color;
  final String subtitle;
  final VoidCallback onTap;
}

/// The department's logo in a circle; used on the dashboard too.
class DepartmentLogo extends StatelessWidget {
  const DepartmentLogo({super.key, required this.dept, this.size = 80});

  final Department dept;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: dept.color, width: 3),
        boxShadow: [
          BoxShadow(
              color: dept.color.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(dept.logo, fit: BoxFit.contain),
    );
  }
}

// =====================================================================
// FOLDER SCREENS
// =====================================================================
Scaffold _folderScaffold(String title, List<Widget> children) => Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child:
              ListView(padding: const EdgeInsets.all(20), children: children),
        ),
      ),
    );

Widget _sectionTitle(String text, int count) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(children: [
        Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14.5)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF334155),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ),
      ]),
    );

Widget _emptyText(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(text,
          textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
    );

Widget _personTile(_Row u, Color color, {String? extra, VoidCallback? onTap}) {
  final name = u['full_name'] as String? ?? 'Unknown';
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(name,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${u['id_number'] ?? ''}${extra == null ? '' : ' • $extra'}',
            style: const TextStyle(color: _muted, fontSize: 12)),
        trailing: onTap == null
            ? null
            : const Icon(Icons.chevron_right_rounded, color: _dim),
      ),
    ),
  );
}

/// Students grouped by batch, taken from their ID (IT-23-01003 → 2023).
class _StudentsFolder extends StatelessWidget {
  const _StudentsFolder({required this.dept, required this.students});

  final Department dept;
  final List<_Row> students;

  static String batchOf(_Row u) {
    final parts = (u['id_number'] as String? ?? '').split('-');
    final yy = parts.length == 3 ? int.tryParse(parts[1]) : null;
    return yy == null ? 'Other' : 'Batch 20${yy.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final byBatch = <String, List<_Row>>{};
    for (final s in students) {
      byBatch.putIfAbsent(batchOf(s), () => []).add(s);
    }
    final batches = byBatch.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final list in byBatch.values) {
      list.sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
    }

    return _folderScaffold('${dept.code} Students', [
      if (students.isEmpty) _emptyText('No student accounts yet.'),
      for (final batch in batches) ...[
        _sectionTitle(batch, byBatch[batch]!.length),
        ...byBatch[batch]!.map((s) => _personTile(s, const Color(0xFF38BDF8))),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

/// Faculty accounts; each opens that person's uploads.
class _FacultyFolder extends StatelessWidget {
  const _FacultyFolder(
      {required this.dept, required this.faculty, required this.materials});

  final Department dept;
  final List<_Row> faculty;
  final List<_Row> materials;

  @override
  Widget build(BuildContext context) {
    final sorted = [...faculty]
      ..sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
    return _folderScaffold('${dept.code} Faculty', [
      if (faculty.isEmpty) _emptyText('No faculty accounts yet.'),
      for (final f in sorted)
        Builder(builder: (context) {
          final uploads = materials
              .where((m) => m['uploaded_by'] == f['id_number'])
              .toList();
          return _personTile(
            f,
            const Color(0xFF818CF8),
            extra: '${uploads.length} upload${uploads.length == 1 ? '' : 's'}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _MaterialsList(
                  title: f['full_name'] as String? ?? 'Uploads',
                  materials: uploads,
                  emptyText: 'Nothing uploaded yet.',
                  groupByYear: true,
                ),
              ),
            ),
          );
        }),
    ]);
  }
}

/// Reading materials, one folder per faculty member who uploaded them.
class _UploadersFolder extends StatelessWidget {
  const _UploadersFolder(
      {required this.dept, required this.materials, required this.names});

  final Department dept;
  final List<_Row> materials;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    final byUploader = <String, List<_Row>>{};
    for (final m in materials) {
      final id = m['uploaded_by'] as String?;
      final name = (id != null && (names[id] ?? '').isNotEmpty)
          ? names[id]!
          : (m['instructor'] as String? ?? 'Unknown faculty');
      byUploader.putIfAbsent(name, () => []).add(m);
    }
    final uploaders = byUploader.keys.toList()..sort();

    return _folderScaffold('${dept.code} Reading Materials', [
      if (materials.isEmpty) _emptyText('No reading materials uploaded yet.'),
      for (final name in uploaders)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.folder_rounded,
                  color: Color(0xFFFBBF24), size: 34),
              title: Text(name,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text(_summary(byUploader[name]!),
                  style: const TextStyle(color: _muted, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: _dim),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _MaterialsList(
                    title: name,
                    materials: byUploader[name]!,
                    emptyText: 'Nothing here yet.',
                    groupByYear: true,
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  static String _summary(List<_Row> items) {
    final approved = items.where((m) => m['status'] == 'approved').length;
    final pending = items.where((m) => m['status'] == 'pending').length;
    return '${items.length} material${items.length == 1 ? '' : 's'} • '
        '$approved approved • $pending pending';
  }
}

/// Materials with their status; tap one to preview it.
class _MaterialsList extends StatelessWidget {
  const _MaterialsList({
    required this.title,
    required this.materials,
    required this.emptyText,
    this.groupByYear = false,
  });

  final String title;
  final List<_Row> materials;
  final String emptyText;
  final bool groupByYear;

  static const _years = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

  @override
  Widget build(BuildContext context) {
    if (!groupByYear || materials.isEmpty) {
      return _folderScaffold(title, [
        if (materials.isEmpty) _emptyText(emptyText),
        ...materials.map((m) => _tile(context, m)),
      ]);
    }

    final byYear = <String, List<_Row>>{};
    for (final m in materials) {
      byYear.putIfAbsent('${m['year'] ?? 'Other'}', () => []).add(m);
    }
    int rank(String y) {
      final i = _years.indexOf(y);
      return i < 0 ? 99 : i;
    }

    final years = byYear.keys.toList()
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    for (final list in byYear.values) {
      list.sort((a, b) =>
          '${a['term']}${a['code']}'.compareTo('${b['term']}${b['code']}'));
    }

    return _folderScaffold(title, [
      for (final y in years) ...[
        _sectionTitle(y, byYear[y]!.length),
        ...byYear[y]!.map((m) => _tile(context, m)),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _tile(BuildContext context, _Row m) {
    final status = m['status'] as String? ?? 'pending';
    final (label, color) = switch (status) {
      'approved' => ('Approved', const Color(0xFF22C55E)),
      'rejected' => ('Sent back', const Color(0xFFEF4444)),
      _ => ('Pending', const Color(0xFFFBBF24)),
    };
    final isSyllabus = m['type'] == 'syllabus';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () => previewMaterialRow(context, m),
          leading: Icon(
              isSyllabus
                  ? Icons.table_chart_outlined
                  : Icons.picture_as_pdf_outlined,
              color: const Color(0xFF38BDF8)),
          title: Text(m['title'] as String? ?? 'Untitled',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${m['code'] ?? ''} • ${m['year'] ?? ''} • ${m['term'] ?? ''}'
              '\nBy ${m['instructor'] ?? 'faculty'} • '
              '${timeAgo(m['uploaded_at'])}',
              style: const TextStyle(color: _muted, fontSize: 12)),
          isThreeLine: true,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              const Icon(Icons.visibility_outlined, color: _dim, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
