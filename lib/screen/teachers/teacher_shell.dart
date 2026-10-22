import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../account_settings_screen.dart';
import 'teacher_dashboard_screen.dart';
import 'teacher_upload_screen.dart';
import 'teacher_notifications_screen.dart';
import 'teacher_activity_logs_screen.dart';

class TeacherShell extends StatefulWidget {
  final UserSession session;

  const TeacherShell({super.key, required this.session});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  // Flowchart order: 0 Upload, 1 Notifications, 2 Dashboard,
  // 3 Activity Logs, 4 Profile. Opens on the Dashboard.
  static const _dashboardTab = 2;
  int _selectedTab = _dashboardTab;
  late final _unreadStream =
      NotificationService.getUnreadCount(widget.session.idNumber);

  String _getAppTitle() {
    switch (_selectedTab) {
      case 0:
        return 'Upload Material';
      case 1:
        return 'Notifications';
      case 2:
        return 'Dashboard';
      case 3:
        return 'Activity Logs';
      default:
        return 'Profile';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        title:
            Text(_getAppTitle(), style: const TextStyle(color: Colors.white)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                widget.session.department,
                style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
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
            index: _selectedTab,
            children: [
              TeacherUploadScreen(
                session: widget.session,
                onBackToDashboard: () =>
                    setState(() => _selectedTab = _dashboardTab),
              ),
              TeacherNotificationsScreen(session: widget.session),
              TeacherDashboardScreen(session: widget.session),
              TeacherActivityLogsScreen(session: widget.session),
              _buildProfileTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _unreadStream,
        builder: (context, snapshot) {
          final unreadCount = snapshot.data?.length ?? 0;
          return BottomNavigationBar(
            currentIndex: _selectedTab,
            onTap: (i) {
              setState(() => _selectedTab = i);
              // Opening Notifications clears the badge.
              if (i == 1) {
                NotificationService.markAllRead(widget.session.idNumber);
              }
            },
            backgroundColor: const Color(0xFF1C2541),
            selectedItemColor: const Color(0xFF818CF8),
            unselectedItemColor: const Color(0xFF64748B),
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: const TextStyle(fontSize: 11),
            unselectedLabelStyle: const TextStyle(fontSize: 10),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.upload_file_outlined),
                activeIcon: Icon(Icons.upload_file),
                label: 'Upload',
              ),
              BottomNavigationBarItem(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 14,
                            minHeight: 14,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                label: 'Notifications',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded),
                label: 'Activity',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        Center(
          child: CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFF818CF8).withValues(alpha: 0.2),
            child: const Icon(Icons.person, size: 50, color: Color(0xFF818CF8)),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(widget.session.fullName,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text('ID: ${widget.session.idNumber}',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF818CF8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(widget.session.department,
                style: const TextStyle(
                    color: Color(0xFF818CF8),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 40),
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: const Color(0xFF1C2541),
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const Icon(Icons.manage_accounts_outlined,
                  color: Color(0xFF818CF8)),
              title: const Text('Account Settings',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Change your password',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Color(0xFF64748B)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          AccountSettingsScreen(session: widget.session))),
            ),
          ),
        ),
        _profileTile(Icons.info_outline, 'About Edushelf', 'Version 1.0.0'),
        _profileTile(
            Icons.school_outlined, 'Department', widget.session.department),
        _profileTile(Icons.badge_outlined, 'Role', 'Faculty'),
      ],
    );
  }

  Widget _profileTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF94A3B8), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          Text(value,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
        ],
      ),
    );
  }
}
