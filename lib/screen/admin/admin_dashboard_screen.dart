import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../models/learning_material.dart';
import '../account_settings_screen.dart';
import '../syllabus_screen.dart';
import '../teachers/teacher_notifications_screen.dart';
import '../../services/admin_service.dart';
import 'bulk_import_screen.dart';
import 'password_requests_screen.dart';
import 'user_account_dialogs.dart';

class AdminDashboardScreen extends StatefulWidget {
  final UserSession session;

  const AdminDashboardScreen({super.key, required this.session});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  String _userSearch = '';

  /// Materials tab view: 'pending', 'approved' or 'archived'.
  String _materialsView = 'pending';
  late final Stream<List<Map<String, dynamic>>> _materialsStream =
      SupabaseService.client
          .from(SupabaseService.materialsTable)
          .stream(primaryKey: ['id'])
          .order('uploaded_at', ascending: false)
          .map((rows) => rows.cast<Map<String, dynamic>>());

  // Open "forgot password" requests, for the badges.
  int _pendingRequests = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _requestsSub;

  int get _totalRequests => _pendingRequests;

  int _unreadNotifications = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationsSub;

  @override
  void initState() {
    super.initState();
    _requestsSub = AdminService.pendingPasswordRequests().listen(
      (rows) {
        if (mounted) setState(() => _pendingRequests = rows.length);
      },
      onError: (_) {}, // Not set up on the server yet.
    );
    _notificationsSub =
        NotificationService.getUnreadCount(widget.session.idNumber).listen(
      (rows) {
        if (mounted) setState(() => _unreadNotifications = rows.length);
      },
      onError: (_) {},
    );
  }

  void _openNotifications() {
    NotificationService.markAllRead(widget.session.idNumber);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1C2541),
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Notifications',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          body: TeacherNotificationsScreen(
            session: widget.session,
            emptyHint: "You'll see new uploads and password requests here.",
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _notificationsSub?.cancel();
    super.dispose();
  }

  final List<String> _titles = [
    'Dashboard',
    'User Management',
    'Materials',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        title: Text(_titles[_selectedIndex],
            style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: _unreadNotifications > 0,
              label: Text('$_unreadNotifications'),
              child:
                  const Icon(Icons.notifications_outlined, color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await AuthService.logout();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _buildOverviewTab(),
              _buildUsersTab(),
              _buildMaterialsTab(),
              _buildSettingsTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        backgroundColor: const Color(0xFF1C2541),
        selectedItemColor: const Color(0xFFFBBF24),
        unselectedItemColor: const Color(0xFF64748B),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
          BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: _totalRequests > 0,
                label: Text('$_totalRequests'),
                child: const Icon(Icons.people_outline),
              ),
              label: 'Users'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.library_books_outlined), label: 'Materials'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }

  // ================================================
  // TAB 0: OVERVIEW
  // ================================================
  Widget _buildOverviewTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client.from(SupabaseService.usersTable).stream(
          primaryKey: ['id']).map((rows) => rows.cast<Map<String, dynamic>>()),
      builder: (context, usersSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: SupabaseService.client
              .from(SupabaseService.materialsTable)
              .stream(primaryKey: ['id']).map(
                  (rows) => rows.cast<Map<String, dynamic>>()),
          builder: (context, materialsSnap) {
            final users = usersSnap.data ?? [];
            final materials = materialsSnap.data ?? [];

            final userCount = users.length;
            final materialCount = materials.length;

            final pendingMaterials =
                materials.where((m) => m['status'] == 'pending').length;
            final approvedMaterials =
                materials.where((m) => m['status'] == 'approved').length;

            final cards = [
              _statCard('Total Users', '$userCount', Icons.people_alt_outlined,
                  const Color(0xFF38BDF8)),
              _statCard('Materials', '$materialCount', Icons.menu_book_outlined,
                  const Color(0xFF10B981)),
              _statCard('Pending Materials', '$pendingMaterials',
                  Icons.hourglass_top_rounded, const Color(0xFFFBBF24)),
              _statCard('Approved Materials', '$approvedMaterials',
                  Icons.check_circle_outline, const Color(0xFF22C55E)),
            ];

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Admin Overview',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 20),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cards.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    childAspectRatio: 1.6,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) => cards[index],
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statCard(String label, String count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Text(count,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  // ================================================
  // TAB 1: USERS
  // ================================================
  Widget _buildUsersTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseService.client
          .from(SupabaseService.usersTable)
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) => rows.cast<Map<String, dynamic>>()),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFBBF24)));
        }

        final q = _userSearch.trim().toLowerCase();
        final users = (snapshot.data ?? []).where((u) {
          if (q.isEmpty) return true;
          return '${u['full_name'] ?? ''} ${u['id_number'] ?? ''}'
              .toLowerCase()
              .contains(q);
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: users.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _buildUsersHeader(users.length);
            final data = users[index - 1];
            final isMe = data['id_number'] == widget.session.idNumber;
            final docId = data['id']?.toString() ?? '';
            final role = data['role'] ?? 'student';
            final dept = data['department'] ?? '—';

            Color roleColor;
            switch (role) {
              case 'admin':
                roleColor = const Color(0xFFFBBF24);
                break;
              case 'instructor':
                roleColor = const Color(0xFF818CF8);
                break;
              default:
                roleColor = const Color(0xFF38BDF8);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: const Color(0xFF1C2541),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: roleColor.withValues(alpha: 0.15),
                        child: Icon(Icons.person, color: roleColor),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['full_name'] ?? 'Unknown',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                            Text('ID: ${data['id_number'] ?? '—'}',
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8), fontSize: 12)),
                            Text('${role.toUpperCase()} • $dept',
                                style: TextStyle(
                                    color: roleColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit account',
                        icon: const Icon(Icons.edit_outlined,
                            color: Color(0xFF94A3B8)),
                        onPressed: () => showEditUserDialog(context, data),
                      ),
                      if (!isMe)
                        IconButton(
                          tooltip: 'Delete account',
                          icon: const Icon(Icons.delete_outline,
                              color: Color(0xFFEF4444)),
                          onPressed: () => _confirmDeleteUser(
                              docId, data['full_name'] ?? ''),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestBanners() {
    return Column(
      children: [
        _requestBanner(
          count: _pendingRequests,
          icon: Icons.lock_reset_rounded,
          title: 'Password Requests',
          waiting: (n) => '$n password reset${n == 1 ? '' : 's'} to approve',
          screen: const PasswordRequestsScreen(),
        ),
      ],
    );
  }

  Widget _requestBanner({
    required int count,
    required IconData icon,
    required String title,
    required String Function(int) waiting,
    required Widget screen,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: count > 0
            ? const Color(0xFFFBBF24).withValues(alpha: 0.12)
            : const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: Icon(icon, color: const Color(0xFFFBBF24)),
          ),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Text(
            count == 0 ? 'No one is waiting' : waiting(count),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: Color(0xFF64748B)),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => screen)),
        ),
      ),
    );
  }

  Widget _buildUsersHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildRequestBanners(),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => showCreateUserDialog(context),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  label: const Text('Create Account',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    side: const BorderSide(color: Color(0xFFFBBF24)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BulkImportScreen())),
                  icon: const Icon(Icons.upload_file_rounded, size: 20),
                  label: const Text('Import CSV',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (v) => setState(() => _userSearch = v),
            decoration: InputDecoration(
              hintText: 'Search by name or ID number...',
              hintStyle: const TextStyle(color: Color(0xFF64748B)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFF1C2541),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            count == 0
                ? 'No accounts found.'
                : '$count account${count == 1 ? '' : 's'}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteUser(String docId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title:
            const Text('Delete User?', style: TextStyle(color: Colors.white)),
        content: Text('Delete "$name"? This cannot be undone.',
            style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              await SupabaseService.client
                  .from(SupabaseService.usersTable)
                  .delete()
                  .eq('id', docId);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ================================================
  // TAB 2: MATERIALS
  // ================================================
  Widget _buildMaterialsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _materialsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFBBF24)));
        }

        // Filtered here so a decision moves the material out of the view
        // immediately. Materials sent back for revision ('rejected') are
        // with the faculty member and don't appear in any view.
        final all = snapshot.data ?? [];
        int count(String status) =>
            all.where((m) => (m['status'] ?? 'pending') == status).length;
        final shown = all
            .where((m) => (m['status'] ?? 'pending') == _materialsView)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                selectedForegroundColor: Colors.black,
                selectedBackgroundColor: const Color(0xFFFBBF24),
                side: const BorderSide(color: Color(0xFF334155)),
              ),
              segments: [
                ButtonSegment(
                    value: 'pending',
                    label: Text('Pending (${count('pending')})')),
                ButtonSegment(
                    value: 'approved',
                    label: Text('Approved (${count('approved')})')),
                ButtonSegment(
                    value: 'archived',
                    label: Text('Archived (${count('archived')})')),
              ],
              selected: {_materialsView},
              onSelectionChanged: (v) =>
                  setState(() => _materialsView = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              switch (_materialsView) {
                'pending' => 'Waiting for review. Approve to publish, or '
                    'send back for revision.',
                'approved' => 'Visible to students. Archive to take one '
                    'down without deleting it.',
                _ => 'Hidden from students. Restore to publish again, or '
                    'delete permanently.',
              },
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Text(
                  switch (_materialsView) {
                    'pending' => 'Nothing to review right now.',
                    'approved' => 'No approved materials yet.',
                    _ => 'The archive is empty.',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
              )
            else
              ...shown.map(_materialCard),
          ],
        );
      },
    );
  }

  Widget _materialCard(Map<String, dynamic> m) {
    final status = m['status'] as String? ?? 'pending';
    final isSyllabus = m['type'] == 'syllabus';

    Widget action(String label, IconData icon, Color bg, Color fg,
            VoidCallback onPressed) =>
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: bg, foregroundColor: fg),
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      isSyllabus
                          ? Icons.table_chart_outlined
                          : Icons.picture_as_pdf_outlined,
                      size: 18,
                      color: const Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m['title'] ?? 'Untitled',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                  if (isSyllabus)
                    IconButton(
                      tooltip: 'Preview syllabus',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.visibility_outlined,
                          color: Color(0xFF38BDF8)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SyllabusScreen(
                              material: LearningMaterial.fromRow(m)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  '${m['code']} • ${m['program']} • ${m['year']}'
                  '${isSyllabus ? ' • Syllabus' : ''}',
                  style:
                      const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              Text('By ${m['instructor'] ?? m['uploaded_by'] ?? 'faculty'}',
                  style:
                      const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
              const SizedBox(height: 10),
              Row(
                children: switch (status) {
                  'pending' => [
                      action('Approve', Icons.check, const Color(0xFF22C55E),
                          Colors.white, () => _approveMaterial(m)),
                      const SizedBox(width: 8),
                      action('Revise', Icons.edit_note, const Color(0xFFFBBF24),
                          Colors.black, () => _rejectMaterial(m)),
                    ],
                  'approved' => [
                      action(
                          'Archive',
                          Icons.archive_outlined,
                          const Color(0xFF334155),
                          Colors.white,
                          () => _archiveMaterial(m)),
                    ],
                  _ => [
                      action(
                          'Restore',
                          Icons.unarchive_outlined,
                          const Color(0xFF22C55E),
                          Colors.white,
                          () => _setMaterialStatus(m, 'approved',
                              done: 'Restored. Students can see it again.')),
                      const SizedBox(width: 8),
                      action(
                          'Delete permanently',
                          Icons.delete_forever,
                          const Color(0xFFEF4444),
                          Colors.white,
                          () => _deleteMaterial(m)),
                    ],
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveMaterial(Map<String, dynamic> m) async {
    await _updateMaterialStatus(m['id'].toString(), 'approved',
        m['title'] ?? '', m['uploaded_by'] ?? '',
        program: m['program'] as String?);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Approved. It is now in the Approved list and visible '
            'to students.')));
  }

  Future<void> _archiveMaterial(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('Archive material?',
            style: TextStyle(color: Colors.white)),
        content: Text(
            '"${m['title']}" will be hidden from students. You can restore '
            'it from the Archived list at any time.',
            style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFBBF24),
                foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _setMaterialStatus(m, 'archived',
        done: 'Archived. Find it under Archived to restore it.');
  }

  Future<void> _setMaterialStatus(Map<String, dynamic> m, String status,
      {required String done}) async {
    try {
      await SupabaseService.client
          .from(SupabaseService.materialsTable)
          .update({'status': status}).eq('id', m['id']);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save. Check your connection.')));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _updateMaterialStatus(
      String docId, String status, String title, String uploadedBy,
      {String? notes, String? program}) async {
    // 1. Update material status (and the admin's revision notes)
    await SupabaseService.client.from(SupabaseService.materialsTable).update({
      'status': status,
      'revision_notes': status == 'rejected' ? notes : null,
    }).eq('id', docId);

    // 2. Send notification to the faculty
    final notifTitle =
        status == 'approved' ? 'Material Approved' : 'Revision Requested';
    final notifBody = status == 'approved'
        ? '"$title" has been approved.'
        : '"$title" needs revision.'
            '${(notes ?? '').isEmpty ? ' Please review and resubmit.' : ' Admin notes: $notes'}';

    await NotificationService.createNotification(
      to: uploadedBy,
      from: widget.session.idNumber,
      title: notifTitle,
      body: notifBody,
      type: status,
    );

    // 3. Students of that department hear about the new material.
    if (status == 'approved' && program != null) {
      await NotificationService.notifyMany(
        to: await NotificationService.idsWithRole('student',
            department: program),
        from: widget.session.idNumber,
        title: 'New Material Available',
        body: '"$title" is now available in Browse.',
        type: 'student_material',
      );
    }
  }

  /// "Add Revision Notes / Comments" -> rejection + revision notification.
  Future<void> _rejectMaterial(Map<String, dynamic> m) async {
    final notes = await _askNote(
      title: 'Send back for revision',
      message: 'Tell the faculty member what to fix in "${m['title']}".',
      label: 'Revision notes / comments',
      confirm: 'Send',
      required: true,
    );
    if (notes == null) return;
    await _updateMaterialStatus(m['id'].toString(), 'rejected',
        m['title'] ?? '', m['uploaded_by'] ?? '',
        notes: notes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Revision notes sent to the faculty member.')));
  }

  /// Asks for a note. Returns null when cancelled.
  Future<String?> _askNote({
    required String title,
    required String message,
    required String label,
    required String confirm,
    bool required = false,
    Color confirmColor = const Color(0xFFFBBF24),
  }) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: Color(0xFF94A3B8))),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                maxLines: 3,
                maxLength: 300,
                style: const TextStyle(color: Colors.white),
                validator: (v) => required && (v ?? '').trim().isEmpty
                    ? 'Please write a note'
                    : null,
                decoration: InputDecoration(
                  labelText: required ? label : '$label (optional)',
                  labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  counterStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF0B132B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: confirmColor == const Color(0xFFFBBF24)
                    ? Colors.black
                    : Colors.white),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: Text(confirm),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  /// Only from the archive: removes the material and its file for good.
  Future<void> _deleteMaterial(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('Delete permanently?',
            style: TextStyle(color: Colors.white)),
        content: Text(
            '"${m['title']}" and its file will be deleted for good. This '
            'cannot be undone.',
            style: const TextStyle(color: Color(0xFF94A3B8))),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await SupabaseService.client
          .from(SupabaseService.materialsTable)
          .delete()
          .eq('id', m['id']);
      final url = m['file_url'] as String?;
      if (url != null && url.isNotEmpty) {
        await SupabaseService.deleteFile(url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not delete. Check your connection.')));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Deleted permanently.')));
  }

  // ================================================
  // TAB 3: PERMISSIONS
  // ================================================
  // ================================================
  // TAB 4: SETTINGS
  // ================================================
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('System Settings',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 14),
        _adminTile(
            'My Account',
            'View your profile and change your password',
            Icons.manage_accounts_outlined,
            const Color(0xFF38BDF8),
            () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        AccountSettingsScreen(session: widget.session)))),
        _adminTile(
            'Seed Demo Materials',
            'Add sample materials for testing',
            Icons.cloud_upload_outlined,
            const Color(0xFF10B981),
            _seedDemoMaterials),
        _adminTile('Activity Logs', 'View all user activity',
            Icons.receipt_long_outlined, const Color(0xFF818CF8), () {}),
        _adminTile('System Info', 'Version and system details',
            Icons.info_outline, const Color(0xFFFBBF24), () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1C2541),
              title:
                  const Text('Edushelf', style: TextStyle(color: Colors.white)),
              content: const Text(
                  'Version 1.0.0\nAdmin Dashboard\nCollege of Accountancy, Business Management, and Information Technology',
                  style: TextStyle(color: Color(0xFF94A3B8))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK',
                        style: TextStyle(color: Color(0xFF38BDF8)))),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _seedDemoMaterials() async {
    final materials = [
      {
        'title': 'Data Structures & Algorithms in Java',
        'code': 'IT 201',
        'program': 'BSIT',
        'year': '2nd Year',
        'term': '1st Sem',
        'instructor': 'Prof. E. Cruz, MSCS',
        'type': 'learning_material',
        'status': 'pending',
        'uploaded_by': 'IT-T-00001',
      },
      {
        'title': 'Information Assurance & Cybersecurity',
        'code': 'IT 305',
        'program': 'BSIT',
        'year': '3rd Year',
        'term': '2nd Sem',
        'instructor': 'Prof. N. Ramos, MIT',
        'type': 'syllabus',
        'status': 'pending',
        'uploaded_by': 'IT-T-00001',
      },
    ];

    for (final m in materials) {
      await SupabaseService.client
          .from(SupabaseService.materialsTable)
          .insert(m);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Demo materials seeded!'),
          backgroundColor: Color(0xFF10B981)),
    );
  }

  Widget _adminTile(String title, String subtitle, IconData icon, Color color,
      VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
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
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 14.5)),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12)),
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
