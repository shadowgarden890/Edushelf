import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../models/department.dart';
import '../../services/activity_service.dart';
import '../account_settings_screen.dart';
import '../teachers/teacher_notifications_screen.dart';
import '../../services/admin_service.dart';
import 'admin_activity_screen.dart';
import 'bulk_import_screen.dart';
import 'department_screen.dart';
import 'material_preview.dart';
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

  /// Materials tab view: 'pending' or 'approved'.
  String _materialsView = 'pending';
  late final Stream<List<Map<String, dynamic>>> _usersStream =
      SupabaseService.client.from(SupabaseService.usersTable).stream(
          primaryKey: ['id']).map((rows) => rows.cast<Map<String, dynamic>>());
  late final Stream<List<Map<String, dynamic>>> _activityStream =
      ActivityService.getAllActivity(limit: 50);
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
    'Homepage',
    'User Management',
    'Materials',
    'Activity Logs',
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
      body: Row(
        children: [
          _buildSideNav(),
          const VerticalDivider(width: 1, color: Color(0xFF1E293B)),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildOverviewTab(),
                    _buildUsersTab(),
                    _buildMaterialsTab(),
                    const AdminActivityScreen(embedded: true),
                    _buildSettingsTab(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tabs on the left; labels beside the icons on wide screens.
  Widget _buildSideNav() {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final narrow = width < 600; // phones: icons only
    Widget badge(int count, IconData icon) => Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: Icon(icon),
        );

    return NavigationRail(
      extended: wide,
      minExtendedWidth: 210,
      backgroundColor: const Color(0xFF1C2541),
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      minWidth: narrow ? 56 : 72,
      labelType: wide || narrow
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      indicatorColor: const Color(0xFFFBBF24).withValues(alpha: 0.18),
      selectedIconTheme: const IconThemeData(color: Color(0xFFFBBF24)),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF64748B)),
      selectedLabelTextStyle: const TextStyle(
          color: Color(0xFFFBBF24), fontWeight: FontWeight.bold),
      unselectedLabelTextStyle: const TextStyle(color: Color(0xFF94A3B8)),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: wide
            ? const Row(children: [
                Icon(Icons.auto_stories_rounded, color: Color(0xFFFBBF24)),
                SizedBox(width: 8),
                Text('Edushelf Admin',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ])
            : const Icon(Icons.auto_stories_rounded, color: Color(0xFFFBBF24)),
      ),
      destinations: [
        const NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: Text('Homepage')),
        NavigationRailDestination(
            icon: badge(_totalRequests, Icons.people_outline),
            selectedIcon: badge(_totalRequests, Icons.people_rounded),
            label: const Text('Users')),
        const NavigationRailDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books_rounded),
            label: Text('Materials')),
        const NavigationRailDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: Text('Activity')),
        const NavigationRailDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: Text('Settings')),
      ],
    );
  }

  // ================================================
  // TAB 0: OVERVIEW
  // ================================================
  Widget _buildOverviewTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _usersStream,
      builder: (context, usersSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _materialsStream,
          builder: (context, materialsSnap) {
            final users = usersSnap.data ?? [];
            final materials = materialsSnap.data ?? [];

            final students = users.where((u) => u['role'] == 'student').length;
            final faculty =
                users.where((u) => u['role'] == 'instructor').length;
            final pending =
                materials.where((m) => m['status'] == 'pending').toList();
            final approved =
                materials.where((m) => m['status'] == 'approved').length;

            final cards = [
              _statCard('Total Users', '${users.length}',
                  Icons.people_alt_outlined, const Color(0xFF38BDF8),
                  detail: '$students students • $faculty faculty',
                  onTap: () => setState(() => _selectedIndex = 1)),
              _statCard('Materials', '${materials.length}',
                  Icons.menu_book_outlined, const Color(0xFF10B981),
                  detail: 'All departments',
                  onTap: () => setState(() => _selectedIndex = 2)),
              _statCard('Pending Review', '${pending.length}',
                  Icons.hourglass_top_rounded, const Color(0xFFFBBF24),
                  detail: pending.isEmpty ? 'All caught up' : 'Tap to review',
                  onTap: () => setState(() {
                        _selectedIndex = 2;
                        _materialsView = 'pending';
                      })),
              _statCard('Approved', '$approved', Icons.check_circle_outline,
                  const Color(0xFF22C55E),
                  detail: 'Visible to students',
                  onTap: () => setState(() {
                        _selectedIndex = 2;
                        _materialsView = 'approved';
                      })),
            ];

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildWelcome(pending.length),
                const SizedBox(height: 18),
                GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 112,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: cards,
                ),
                const SizedBox(height: 26),
                _overviewHeading('Departments',
                    'Open one to see its users, syllabus and materials'),
                const SizedBox(height: 12),
                GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 270,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final d in Department.all)
                      _departmentCard(d, users, materials),
                  ],
                ),
                const SizedBox(height: 26),
                LayoutBuilder(builder: (context, c) {
                  final review = _buildReviewPanel(pending);
                  final activity = _buildActivityPanel();
                  if (c.maxWidth < 760) {
                    return Column(children: [
                      review,
                      const SizedBox(height: 16),
                      activity,
                    ]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: review),
                      const SizedBox(width: 16),
                      Expanded(child: activity),
                    ],
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWelcome(int pending) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final first = widget.session.fullName.split(' ').first;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A86FF), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$greeting, $first!',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                    pending == 0
                        ? 'No materials are waiting for review.'
                        : '$pending material${pending == 1 ? ' is' : 's are'} '
                            'waiting for your review.',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13.5)),
              ],
            ),
          ),
          const Icon(Icons.auto_stories_rounded,
              color: Colors.white24, size: 64),
        ],
      ),
    );
  }

  Widget _overviewHeading(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(subtitle,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
        ],
      );

  Widget _departmentCard(Department d, List<Map<String, dynamic>> users,
      List<Map<String, dynamic>> materials) {
    final people = users.where((u) => u['department'] == d.code);
    final students = people.where((u) => u['role'] == 'student').length;
    final faculty = people.where((u) => u['role'] == 'instructor').length;
    final mats = materials.where((m) => m['program'] == d.code).length;

    Widget stat(String n, String label) => Expanded(
        child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(children: [
              Text(n,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 10.5)),
            ])));

    return Material(
      color: const Color(0xFF1C2541),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DepartmentScreen(department: d)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: d.color.withValues(alpha: 0.45)),
            gradient: LinearGradient(
              colors: [d.color.withValues(alpha: 0.18), Colors.transparent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, c) => DepartmentLogo(
                        dept: d,
                        size: c.biggest.shortestSide.clamp(60.0, 130.0)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(d.code,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text(d.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 11.5)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  stat('$students', 'Students'),
                  stat('$faculty', 'Faculty'),
                  stat('$mats', 'Materials'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(String title, IconData icon, Color color, String action,
      VoidCallback onAction, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              TextButton(
                onPressed: onAction,
                child: Text(action, style: TextStyle(color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _buildReviewPanel(List<Map<String, dynamic>> pending) {
    return _panel(
      'Waiting for review',
      Icons.hourglass_top_rounded,
      const Color(0xFFFBBF24),
      'Review all',
      () => setState(() {
        _selectedIndex = 2;
        _materialsView = 'pending';
      }),
      [
        if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('All caught up!',
                style: TextStyle(color: Color(0xFF94A3B8))),
          ),
        for (final m in pending.take(5))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                m['type'] == 'syllabus'
                    ? Icons.table_chart_outlined
                    : Icons.picture_as_pdf_outlined,
                color: const Color(0xFF38BDF8)),
            title: Text(m['title'] as String? ?? 'Untitled',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white)),
            subtitle: Text(
                '${m['program'] ?? ''} • ${m['instructor'] ?? 'faculty'} • '
                '${timeAgo(m['uploaded_at'])}',
                style:
                    const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5)),
            trailing: IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.visibility_outlined,
                  color: Color(0xFF64748B)),
              onPressed: () => previewMaterialRow(context, m),
            ),
          ),
      ],
    );
  }

  Widget _buildActivityPanel() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _activityStream,
      builder: (context, snap) {
        final logs = snap.data ?? [];
        return _panel(
          'Recent activity',
          Icons.insights_rounded,
          const Color(0xFFF472B6),
          'View all',
          () => setState(() => _selectedIndex = 3),
          [
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No reading activity yet.',
                    style: TextStyle(color: Color(0xFF94A3B8))),
              ),
            for (final r in logs.take(6))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      const Color(0xFFF472B6).withValues(alpha: 0.15),
                  child: Text(
                      '${r['student_name'] ?? '?'}'.isEmpty
                          ? '?'
                          : '${r['student_name']}'[0].toUpperCase(),
                      style: const TextStyle(
                          color: Color(0xFFF472B6),
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
                title: Text(
                    '${r['student_name'] ?? 'A student'} • '
                    '${_actionText(r['action'])} ${r['material_code'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    '${r['department'] ?? ''} • ${timeAgo(r['created_at'])}',
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 11.5)),
              ),
          ],
        );
      },
    );
  }

  static String _actionText(Object? action) => switch (action) {
        'open' => 'opened',
        'read' => 'is reading',
        'progress' => 'stopped reading',
        'bookmark' => 'bookmarked a page in',
        'unbookmark' => 'removed a bookmark in',
        'download' => 'downloaded',
        _ => 'used',
      };

  Widget _statCard(String label, String count, IconData icon, Color color,
      {required String detail, required VoidCallback onTap}) {
    return Material(
      color: const Color(0xFF1C2541),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(count,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                _ => 'Visible to students. Tap the eye to preview one.',
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
                    _ => 'No approved materials yet.',
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
                  IconButton(
                    tooltip:
                        isSyllabus ? 'Preview syllabus' : 'Preview material',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.visibility_outlined,
                        color: Color(0xFF38BDF8)),
                    onPressed: () => previewMaterialRow(context, m),
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
                children: [
                  if (status == 'pending') ...[
                    action('Approve', Icons.check, const Color(0xFF22C55E),
                        Colors.white, () => _approveMaterial(m)),
                    const SizedBox(width: 8),
                    action('Revise', Icons.edit_note, const Color(0xFFFBBF24),
                        Colors.black, () => _rejectMaterial(m)),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline,
                        color: Color(0xFFEF4444)),
                    onPressed: () => _deleteMaterial(m),
                  ),
                ],
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

  /// Removes the material and its file for good, after asking.
  Future<void> _deleteMaterial(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('Delete permanently?',
            style: TextStyle(color: Colors.white)),
        content: Text(
            '"${m['title']}" and its file will be deleted for good, and '
            'students will no longer see it. This cannot be undone.',
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
            'Activity Logs',
            'What students open, read, bookmark and download',
            Icons.receipt_long_outlined,
            const Color(0xFF818CF8),
            () => setState(() => _selectedIndex = 3)),
        _adminTile('System Info', 'Version and system details',
            Icons.info_outline, const Color(0xFFFBBF24), () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1C2541),
              title:
                  const Text('Edushelf', style: TextStyle(color: Colors.white)),
              content: const Text(
                  'Version 1.0.0\nAdmin Homepage\nCollege of Accountancy, Business Management, and Information Technology',
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
