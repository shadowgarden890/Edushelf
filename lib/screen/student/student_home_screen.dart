import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/learning_material.dart';
import '../../models/user_session.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../widgets/book_cover_card.dart';
import '../../widgets/offline_notice.dart';
import '../account_settings_screen.dart';
import '../book_pages_directory_screen.dart';
import '../syllabus_screen.dart';
import '../teachers/teacher_notifications_screen.dart';
import 'download_queue_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  final UserSession session;

  const StudentHomeScreen({super.key, required this.session});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  // 0 Browse, 1 Updates, 2 My Library, 3 History, 4 Settings
  int _selectedTabIndex = 2;
  int _unreadNotifications = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationsSub;
  String _selectedYear = 'All Years';
  String _searchQuery = '';
  String _librarySearchQuery = '';
  bool _isOnline = true;
  late StreamSubscription<bool> _connectivitySub;
  late Stream<List<Map<String, dynamic>>> _materialsStream;

  LibraryService get _library => LibraryService.instance;
  DownloadService get _downloads => DownloadService.instance;

  @override
  void initState() {
    super.initState();

    _library.load(widget.session.idNumber);
    _downloads.setSession(widget.session);

    // Badge for 'Access Granted' / 'Request Denied' and other alerts.
    _notificationsSub =
        NotificationService.getUnreadCount(widget.session.idNumber).listen(
      (rows) {
        if (mounted) setState(() => _unreadNotifications = rows.length);
      },
      onError: (_) {},
    );

    // Real-time stream of approved materials in student's department
    _materialsStream = SupabaseService.client
        .from(SupabaseService.materialsTable)
        .stream(primaryKey: ['id'])
        .eq('program', widget.session.department)
        .order('uploaded_at', ascending: false)
        // Status is checked here so a material sent back for revision
        // disappears right away (a live stream keeps rows that stop
        // matching a server filter).
        .map((rows) => rows
            .cast<Map<String, dynamic>>()
            .where((r) => r['status'] == 'approved')
            .toList());

    _checkConnectivity();
    _connectivitySub = ConnectivityService.onStatusChanged().listen((online) {
      if (mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _checkConnectivity() async {
    final online = await ConnectivityService.isOnline();
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    _notificationsSub?.cancel();
    super.dispose();
  }

  // Convert Supabase rows to LearningMaterial models
  List<LearningMaterial> _toMaterials(List<Map<String, dynamic>> rows) {
    return rows.map((row) {
      final material = LearningMaterial.fromRow(row);
      final saved = _library.entryFor(material.id)?.material;
      if (saved != null) {
        material.totalPages = saved.totalPages;
        material.currentPage = saved.currentPage;
      }
      return material;
    }).toList();
  }

  CoverDownloadState _downloadStateFor(LearningMaterial material) {
    final entry = _library.entryFor(material.id);
    if (entry?.isFullyDownloaded == true) return CoverDownloadState.full;
    if (_downloads.activeTaskFor(material.id) != null) {
      return CoverDownloadState.inProgress;
    }
    if (entry?.downloadedPages.isNotEmpty == true) {
      return CoverDownloadState.partial;
    }
    return CoverDownloadState.none;
  }

  Widget _buildCard(LearningMaterial material) {
    return BookCoverCard(
      material: material,
      onTap: () => _openBookDirectory(material),
      isFavorite: _library.isFavorite(material.id),
      onFavoriteTap: () => _toggleFavorite(material),
      downloadState: _downloadStateFor(material),
      // Syllabi are read online only.
      onDownloadTap: LibraryService.supportsDownloads &&
              material.hasFile &&
              !material.isSyllabus
          ? () => _downloadFull(material)
          : null,
    );
  }

  Future<void> _toggleFavorite(LearningMaterial material) async {
    final wasFavorite = _library.isFavorite(material.id);
    await _library.toggleFavorite(material);
    if (!mounted) return;
    _snack(
        wasFavorite ? 'Removed from your library.' : 'Saved to your library.');
  }

  void _downloadFull(LearningMaterial material) {
    final state = _downloadStateFor(material);
    if (state == CoverDownloadState.full) {
      _snack('Already downloaded. Find it in My Library.');
      return;
    }
    if (state == CoverDownloadState.inProgress) {
      _openDownloadQueue();
      return;
    }
    // Syllabi need admin permission, which is handled on the details page.
    if (material.isSyllabus) {
      _openBookDirectory(material);
      return;
    }
    if (_downloads.enqueueFull(material)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Downloading "${material.title}"...'),
          action: SnackBarAction(
            label: 'View queue',
            textColor: const Color(0xFF38BDF8),
            onPressed: _openDownloadQueue,
          ),
        ));
    }
  }

  void _openDownloadQueue() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DownloadQueueScreen()));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openBookDirectory(LearningMaterial material) {
    // A syllabus is open to everyone and read as text, not page by page.
    if (material.isSyllabus) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SyllabusScreen(material: material, session: widget.session),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookPagesDirectoryScreen(
          material: material,
          onProgressUpdated: () => setState(() {}),
          session: widget.session,
        ),
      ),
    );
  }

  String _getAppTitle() {
    switch (_selectedTabIndex) {
      case 0:
        return 'Browse Catalog';
      case 1:
        return 'Material Updates';
      case 2:
        return 'My Library';
      case 3:
        return 'Reading History';
      case 4:
        return 'Settings';
      default:
        return 'Edushelf';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        elevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: Icon(Icons.auto_stories_rounded,
              color: Color(0xFF38BDF8), size: 26),
        ),
        title: Text(
          _getAppTitle(),
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
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
        ],
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              color: const Color(0xFFFBBF24),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, size: 16, color: Colors.black),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline Mode — downloaded materials in My Library '
                      'still work',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _materialsStream,
              builder: (context, snapshot) => ListenableBuilder(
                listenable: Listenable.merge([_library, _downloads]),
                builder: (context, _) {
                  final materials = _toMaterials(snapshot.data ?? []);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: IndexedStack(
                        index: _selectedTabIndex,
                        children: [
                          _buildBrowseTab(materials),
                          _buildUpdatesTab(materials),
                          _buildMyLibraryTab(),
                          _buildHistoryTab(),
                          _buildSettingsTab(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (index) => setState(() => _selectedTabIndex = index),
        backgroundColor: const Color(0xFF1C2541),
        selectedItemColor: const Color(0xFF38BDF8),
        unselectedItemColor: const Color(0xFF64748B),
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Browse'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.feed_outlined),
              activeIcon: Icon(Icons.feed),
              label: 'Updates'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.download_done_rounded), label: 'My Library'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded), label: 'History'),
          BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: _unreadNotifications > 0,
                label: Text('$_unreadNotifications'),
                child: const Icon(Icons.settings_outlined),
              ),
              activeIcon: const Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }

  // TAB 0: MY LIBRARY — hearted or downloaded materials (works offline)
  Widget _buildMyLibraryTab() {
    final materials = _library.entries.map((e) => e.material).toList();
    final filtered = materials.where((m) {
      if (_librarySearchQuery.isEmpty) return true;
      final q = _librarySearchQuery.toLowerCase();
      return m.title.toLowerCase().contains(q) ||
          m.code.toLowerCase().contains(q) ||
          m.instructor.toLowerCase().contains(q);
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Welcome banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3A86FF), Color(0xFF00B4D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome back,',
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(
                      widget.session.fullName.isEmpty
                          ? 'Student!'
                          : widget.session.fullName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ID: ${widget.session.idNumber}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    size: 36, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Search bar
        TextField(
          style: const TextStyle(color: Colors.white),
          onChanged: (val) => setState(() => _librarySearchQuery = val),
          decoration: InputDecoration(
            hintText: 'Search your library...',
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
            filled: true,
            fillColor: const Color(0xFF1C2541),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Downloaded & Saved',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(
              '${filtered.length} item${filtered.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2541),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(Icons.inbox_outlined, color: Color(0xFF64748B), size: 42),
                SizedBox(height: 12),
                Text(
                  'Your library is empty.\nOpen Browse and download a '
                  'material, or tap the heart to save it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 0.62,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemBuilder: (context, index) => _buildCard(filtered[index]),
          ),
      ],
    );
  }

  // TAB 1: HISTORY — opened or downloaded materials (works offline)
  Widget _buildHistoryTab() {
    final history = _library.history;

    if (history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No reading history yet.\nMaterials you open or download '
            'will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Recently Opened & Downloaded',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 14),
        ...history.map(_buildHistoryRow),
      ],
    );
  }

  Widget _buildHistoryRow(LibraryEntry entry) {
    final m = entry.material;
    final String status;
    final Color statusColor;
    if (entry.isFullyDownloaded) {
      status = 'Downloaded • available offline';
      statusColor = const Color(0xFF10B981);
    } else if (entry.downloadedPages.isNotEmpty) {
      final n = entry.downloadedPages.length;
      status = '$n ${n == 1 ? 'page' : 'pages'} downloaded';
      statusColor = const Color(0xFF10B981);
    } else {
      status = 'Opened ${_timeAgo(entry.lastAccessedAt)}';
      statusColor = const Color(0xFF64748B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openBookDirectory(m),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: m.coverGradient),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(m.program,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.code,
                          style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      Text(m.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(status,
                          style: TextStyle(color: statusColor, fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: entry.isFavorite
                      ? 'Remove from library'
                      : 'Add to library',
                  icon: Icon(
                    entry.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: entry.isFavorite
                        ? const Color(0xFFF43F5E)
                        : const Color(0xFF64748B),
                  ),
                  onPressed: () => _toggleFavorite(m),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${time.month}/${time.day}/${time.year}';
  }

  // TAB 2: UPDATES (blocked offline)
  Widget _buildUpdatesTab(List<LearningMaterial> materials) {
    if (!_isOnline) {
      return OfflineNotice(
        featureName: 'Updates',
        onRetry: _checkConnectivity,
      );
    }

    final recent = materials.take(6).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${widget.session.department} Module Bulletins',
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 14),
        if (recent.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('No new materials yet.',
                  style: TextStyle(color: Color(0xFF94A3B8))),
            ),
          )
        else
          ...recent.map((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: const Color(0xFF1C2541),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openBookDirectory(item),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF3A86FF).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.fiber_new_rounded,
                              color: Color(0xFF38BDF8), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.program} • ${item.code}',
                                  style: const TextStyle(
                                      color: Color(0xFF38BDF8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                              Text(item.title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('Instructor: ${item.instructor}',
                                  style: const TextStyle(
                                      color: Color(0xFF94A3B8), fontSize: 11)),
                            ],
                          ),
                        ),
                        if (LibraryService.supportsDownloads &&
                            item.hasFile &&
                            !item.isSyllabus)
                          _updatesDownloadButton(item),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  // TAB 3: BROWSE (blocked offline)
  Widget _buildBrowseTab(List<LearningMaterial> materials) {
    if (!_isOnline) {
      return OfflineNotice(
        featureName: 'Browse Catalog',
        onRetry: _checkConnectivity,
      );
    }

    final filtered = materials.where((item) {
      // A syllabus covers every year, so it shows under any year filter.
      final matchYear = _selectedYear == 'All Years' ||
          item.year == _selectedYear ||
          item.year == 'All Years';
      final matchSearch = item.title
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          item.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.instructor.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchYear && matchSearch;
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          style: const TextStyle(color: Colors.white),
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            hintText: 'Search course code, title, or instructor...',
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
            filled: true,
            fillColor: const Color(0xFF1C2541),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              'All Years',
              '1st Year',
              '2nd Year',
              '3rd Year',
              '4th Year'
            ].map((year) {
              final isSel = _selectedYear == year;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(year),
                  selected: isSel,
                  selectedColor: const Color(0xFF475569),
                  backgroundColor: const Color(0xFF1C2541),
                  labelStyle: TextStyle(
                    color: isSel ? Colors.white : const Color(0xFF94A3B8),
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => setState(() => _selectedYear = year),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${widget.session.department} Catalog',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            Text('${filtered.length} found',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            childAspectRatio: 0.62,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemBuilder: (context, index) => _buildCard(filtered[index]),
        ),
      ],
    );
  }

  Widget _updatesDownloadButton(LearningMaterial item) {
    final state = _downloadStateFor(item);
    return IconButton(
      tooltip: switch (state) {
        CoverDownloadState.full => 'In My Library',
        CoverDownloadState.inProgress => 'Downloading...',
        _ => item.isSyllabus ? 'Request access' : 'Download to Library',
      },
      onPressed: () => _downloadFull(item),
      icon: switch (state) {
        CoverDownloadState.full =>
          const Icon(Icons.download_done_rounded, color: Color(0xFF10B981)),
        CoverDownloadState.inProgress => const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF38BDF8))),
        _ => Icon(
            item.isSyllabus
                ? Icons.lock_outline_rounded
                : Icons.download_rounded,
            color: const Color(0xFF38BDF8)),
      },
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
            emptyHint: "You'll see updates here, like when the admin "
                'answers your syllabus requests.',
          ),
        ),
      ),
    );
  }

  // TAB 4: SETTINGS
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Settings',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 16),
        _buildCleanMoreTile(
          title: 'Change Password',
          subtitle: 'Your profile and password',
          icon: Icons.manage_accounts_outlined,
          color: const Color(0xFFFBBF24),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      AccountSettingsScreen(session: widget.session))),
        ),
        _buildCleanMoreTile(
          title: 'Notifications',
          subtitle: _unreadNotifications == 0
              ? 'Permission results and alerts'
              : '$_unreadNotifications unread',
          icon: Icons.notifications_outlined,
          color: const Color(0xFF818CF8),
          onTap: _openNotifications,
        ),
        _buildCleanMoreTile(
          title: 'Download Queue',
          subtitle: _downloads.activeCount == 0
              ? 'No active downloads'
              : '${_downloads.activeCount} downloading',
          icon: Icons.downloading_rounded,
          color: const Color(0xFF38BDF8),
          onTap: _openDownloadQueue,
        ),
        _buildCleanMoreTile(
          title: 'Guide',
          subtitle: 'Flipbook tutorial',
          icon: Icons.menu_book_outlined,
          color: const Color(0xFF10B981),
          onTap: () =>
              _showDialog('User Guide', 'Tap a material to open the reader.'),
        ),
        _buildCleanMoreTile(
          title: 'About',
          subtitle: 'Edushelf application details',
          icon: Icons.info_outline_rounded,
          color: const Color(0xFF00B4D8),
          onTap: () => _showDialog(
              'About Edushelf', 'Edushelf: Reading Application v1.0.0'),
        ),
        const SizedBox(height: 8),
        const Divider(color: Color(0xFF334155)),
        const SizedBox(height: 8),
        _buildCleanMoreTile(
          title: 'Log Out',
          subtitle: 'Sign out of current session',
          icon: Icons.logout_rounded,
          color: const Color(0xFFEF4444),
          onTap: () => _confirmExit(context),
        ),
      ],
    );
  }

  Widget _buildCleanMoreTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content:
            Text(content, style: const TextStyle(color: Color(0xFF94A3B8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Exit Edushelf?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out of your session?',
            style: TextStyle(color: Color(0xFF94A3B8))),
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
              Navigator.pop(ctx);
              await AuthService.logout();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
