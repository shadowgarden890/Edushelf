import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/learning_material.dart';
import '../models/user_session.dart';
import '../services/connectivity_service.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import 'downloaded_pages_viewer.dart';
import 'physical_flipbook_reader.dart';
import 'student/download_queue_screen.dart';

class BookPagesDirectoryScreen extends StatefulWidget {
  final LearningMaterial material;
  final VoidCallback onProgressUpdated;
  final UserSession? session;

  const BookPagesDirectoryScreen({
    super.key,
    required this.material,
    required this.onProgressUpdated,
    this.session,
  });

  @override
  State<BookPagesDirectoryScreen> createState() =>
      _BookPagesDirectoryScreenState();
}

class _BookPagesDirectoryScreenState extends State<BookPagesDirectoryScreen> {
  bool _loadingPageCount = false;
  String? _pageCountError;

  LibraryService get _library => LibraryService.instance;
  DownloadService get _downloads => DownloadService.instance;

  @override
  void initState() {
    super.initState();
    _loadPageCount();
  }

  /// Materials don't store a page count, so read it from the PDF once.
  Future<void> _loadPageCount() async {
    final mat = widget.material;
    final known = _library.entryFor(mat.id)?.material.totalPages ?? 0;
    if (known > 0) {
      mat.totalPages = known;
      return;
    }
    if (mat.totalPages > 0 || !mat.hasFile) return;

    setState(() {
      _loadingPageCount = true;
      _pageCountError = null;
    });
    try {
      final bytes = await _downloads.loadPdf(mat);
      final doc = await PdfDocument.openData(bytes);
      final pages = doc.pagesCount;
      await doc.close();
      await _library.setPageCount(mat, pages);
    } catch (_) {
      _pageCountError = 'Could not load the page list. Check your '
          'connection and try again.';
    }
    if (mounted) setState(() => _loadingPageCount = false);
  }

  // ================================================
  // OPEN READER
  // ================================================
  Future<void> _openReader(int startingPage) async {
    final url = widget.material.fileUrl;

    // Web: open the PDF in a new browser tab
    if (kIsWeb) {
      if (url == null || url.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No PDF attached to this material.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final opened = await launchUrl(
        Uri.parse(url),
        webOnlyWindowName: '_blank',
      );

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the PDF.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Only single pages downloaded: read those offline as images.
    final entry = _library.entryFor(widget.material.id);
    if (entry != null &&
        !entry.isFullyDownloaded &&
        entry.downloadedPages.isNotEmpty &&
        (entry.downloadedPages.contains(startingPage) ||
            !await ConnectivityService.isOnline())) {
      final pages = entry.downloadedPages.toList()..sort();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadedPagesViewer(
            material: widget.material,
            pages: pages,
            initialPage:
                pages.contains(startingPage) ? startingPage : pages.first,
          ),
        ),
      );
      return;
    }

    // Mobile: use the pdfx-based reader
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhysicalFlipbookReader(
          material: widget.material,
          initialPage: startingPage,
          onProgressSaved: (newPage) {
            setState(() => widget.material.currentPage = newPage);
            widget.onProgressUpdated();
          },
          session: widget.session,
        ),
      ),
    );
  }

  bool get _canShowDownloads =>
      LibraryService.supportsDownloads && widget.material.hasFile;

  // ================================================
  // DOWNLOADS
  // ================================================
  bool _checkCanDownload() {
    if (!_canShowDownloads) {
      _snack('Downloads are only available in the mobile app.');
      return false;
    }
    return true;
  }

  void _downloadAll() {
    if (!_checkCanDownload()) return;
    if (_downloads.enqueueFull(widget.material)) {
      _snackWithQueue('Downloading the whole document to My Library...');
    }
  }

  void _downloadPage(int page) {
    if (!_checkCanDownload()) return;
    if (_downloads.enqueuePage(widget.material, page)) {
      _snackWithQueue('Page $page added to the download queue.');
    }
  }

  Future<void> _deleteDownloads() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('Delete downloads?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'The downloaded pages are removed from this device, and your '
            'reading progress and bookmarks for this material are reset.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _library.deleteDownloads(widget.material.id);
    if (!mounted) return;
    setState(() {
      widget.material.currentPage = 0;
      widget.material.readPages.clear();
    });
    widget.onProgressUpdated();
    _snack('Downloads deleted. Progress and bookmarks were reset.');
  }

  void _openQueue() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DownloadQueueScreen()));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _snackWithQueue(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: 'View queue',
          textColor: const Color(0xFF38BDF8),
          onPressed: _openQueue,
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_library, _downloads]),
      builder: (context, _) => _buildScreen(),
    );
  }

  Widget _buildScreen() {
    final mat = widget.material;
    final entry = _library.entryFor(mat.id);
    final isFavorite = entry?.isFavorite ?? false;
    final queueCount = _downloads.activeCount;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        title: Text(mat.code,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: isFavorite ? 'Remove from library' : 'Save to library',
            icon: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? const Color(0xFFF43F5E) : Colors.white,
            ),
            onPressed: () => _library.toggleFavorite(mat),
          ),
          if (_canShowDownloads)
            IconButton(
              tooltip: 'Download queue',
              onPressed: _openQueue,
              icon: Badge(
                isLabelVisible: queueCount > 0,
                label: Text('$queueCount'),
                child:
                    const Icon(Icons.downloading_rounded, color: Colors.white),
              ),
            ),
          if (entry?.hasDownloads == true)
            PopupMenuButton<String>(
              iconColor: Colors.white,
              color: const Color(0xFF1C2541),
              onSelected: (_) => _deleteDownloads(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete downloads',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // BOOK INFO CARD
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2541),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 100,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: mat.coverGradient),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(mat.program,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(mat.code,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(mat.title,
                                    style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ),
                              if (mat.isSyllabus)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFBBF24)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('SYLLABUS',
                                      style: TextStyle(
                                          color: Color(0xFFFBBF24),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Instructor: ${mat.instructor}',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8), fontSize: 12)),
                          Text('${mat.year} • ${mat.term}',
                              style: const TextStyle(
                                  color: Color(0xFF64748B), fontSize: 11.5)),
                          const SizedBox(height: 12),
                          Text(
                            mat.totalPages == 0
                                ? 'Reading Progress: ${mat.progressPercent}%'
                                : 'Reading Progress: ${mat.progressPercent}% (${mat.readPages.length}/${mat.totalPages} pages read)',
                            style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: mat.progress,
                            backgroundColor: const Color(0xFF0B132B),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF38BDF8)),
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // OPEN READER BUTTON
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A86FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () =>
                    _openReader(mat.currentPage == 0 ? 1 : mat.currentPage),
                icon: const Icon(Icons.auto_stories_rounded, size: 18),
                label: Text(mat.currentPage == 0
                    ? 'Open Reader'
                    : 'Resume from Page ${mat.currentPage}'),
              ),

              // DOWNLOAD WHOLE DOCUMENT
              if (_canShowDownloads) ...[
                const SizedBox(height: 10),
                _buildDownloadAllButton(entry),
              ],

              const SizedBox(height: 24),
              const Divider(color: Color(0xFF334155)),
              const SizedBox(height: 14),

              Row(
                children: [
                  const Expanded(
                    child: Text('Pages Directory:',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                  if (entry != null && entry.hasDownloads)
                    Text(
                      entry.isFullyDownloaded
                          ? 'All pages offline'
                          : '${entry.downloadedPages.length} '
                              '${entry.downloadedPages.length == 1 ? 'page' : 'pages'}'
                              ' offline',
                      style: const TextStyle(
                          color: Color(0xFF10B981), fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              _buildPagesSection(entry),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================
  // PAGES GRID
  // ================================================
  Widget _buildPagesSection(LibraryEntry? entry) {
    final mat = widget.material;

    if (_loadingPageCount) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(
              color: Color(0xFF38BDF8), strokeWidth: 2),
        ),
      );
    }

    if (mat.totalPages == 0) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _pageCountError ?? 'Open the reader to load the page list.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            ),
            if (_pageCountError != null)
              TextButton(
                onPressed: _loadPageCount,
                child: const Text('Retry',
                    style: TextStyle(color: Color(0xFF38BDF8))),
              ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mat.totalPages,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 1.1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (_, index) {
        final pageNum = index + 1;
        return Stack(
          children: [
            Positioned.fill(child: _buildPageTile(pageNum)),
            if (entry?.bookmarks.contains(pageNum) == true)
              const Positioned(
                top: 0,
                left: 8,
                child: IgnorePointer(
                  child: Icon(Icons.bookmark_rounded,
                      size: 18, color: Color(0xFFFBBF24)),
                ),
              ),
            if (_canShowDownloads)
              Positioned(
                top: 0,
                right: 0,
                child: _buildPageDownloadButton(entry, pageNum),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPageTile(int pageNum) {
    final mat = widget.material;
    final isRead = mat.readPages.contains(pageNum);
    final isCurrent = pageNum == mat.currentPage;

    return Material(
      color: isCurrent
          ? const Color(0xFF3A86FF).withValues(alpha: 0.25)
          : (isRead ? const Color(0xFF1C2541) : const Color(0xFF101935)),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openReader(pageNum),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrent
                  ? const Color(0xFF3A86FF)
                  : (isRead
                      ? const Color(0xFF334155)
                      : const Color(0xFF1E293B)),
              width: isCurrent ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRead ? Icons.check_circle_rounded : Icons.menu_book_outlined,
                size: 18,
                color: isCurrent
                    ? const Color(0xFF38BDF8)
                    : (isRead
                        ? const Color(0xFF10B981)
                        : const Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              Text('Page $pageNum',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent
                        ? Colors.white
                        : (isRead ? Colors.white70 : const Color(0xFF64748B)),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageDownloadButton(LibraryEntry? entry, int pageNum) {
    if (entry?.isPageAvailable(pageNum) == true) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.download_done_rounded,
            size: 16, color: Color(0xFF10B981)),
      );
    }

    final task = _downloads.activeTaskFor(widget.material.id, page: pageNum);
    if (task != null) {
      return Padding(
        padding: const EdgeInsets.all(9),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: task.progress,
            color: const Color(0xFF38BDF8),
          ),
        ),
      );
    }

    return IconButton(
      tooltip: 'Download page $pageNum',
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      icon: const Icon(Icons.download_rounded, color: Color(0xFF94A3B8)),
      onPressed: () => _downloadPage(pageNum),
    );
  }

  Widget _buildDownloadAllButton(LibraryEntry? entry) {
    if (entry?.isFullyDownloaded == true) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.download_done_rounded,
            size: 18, color: Color(0xFF10B981)),
        label: const Text('Downloaded — available offline',
            style: TextStyle(color: Color(0xFF10B981))),
      );
    }

    final task = _downloads.activeTaskFor(widget.material.id);
    final progress = task?.progress;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF38BDF8),
        side: const BorderSide(color: Color(0xFF38BDF8)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: task != null ? _openQueue : _downloadAll,
      icon: task != null
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress,
                  color: const Color(0xFF38BDF8)),
            )
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(task == null
          ? 'Download whole document'
          : progress == null
              ? 'Downloading...'
              : 'Downloading ${(progress * 100).toInt()}%'),
    );
  }
}
