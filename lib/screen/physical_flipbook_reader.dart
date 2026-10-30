import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../models/learning_material.dart';
import '../services/activity_service.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import '../widgets/flipbook_view.dart';
import '../widgets/vertical_pages_view.dart';

enum ReaderMode { flipbook, vertical }

class PhysicalFlipbookReader extends StatefulWidget {
  final LearningMaterial material;
  final int initialPage;
  final Function(int) onProgressSaved;
  final dynamic session;

  /// False for the admin's preview: nothing is saved as reading progress.
  final bool trackProgress;

  const PhysicalFlipbookReader({
    super.key,
    required this.material,
    required this.initialPage,
    required this.onProgressSaved,
    this.session,
    this.trackProgress = true,
  });

  @override
  State<PhysicalFlipbookReader> createState() => _PhysicalFlipbookReaderState();
}

class _PhysicalFlipbookReaderState extends State<PhysicalFlipbookReader> {
  late int _currentPage;
  bool _isLoading = true;
  String? _error;
  ReaderMode _mode = ReaderMode.flipbook;

  Uint8List? _bytes;
  int _pageCount = 0;

  // Flipbook: pages rendered to images from this document, one at a time
  // (Android's renderer can only have one page open per document).
  PdfDocument? _renderDocument;
  Future<void> _renderLock = Future.value();
  final _flipbookKey = GlobalKey<FlipbookViewState>();

  // Vertical on desktop: pages rendered like the flipbook (pdfx's scroll
  // view only shows gray there).
  static final _ownVerticalView = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  final _verticalKey = GlobalKey<VerticalPagesViewState>();
  double _pageAspect = 1 / 1.414; // A4 until the first page is measured

  // Vertical on phones: continuous, pinch-zoomable scroll.
  PdfControllerPinch? _pinchController;
  Future<PdfDocument>? _pinchDocument;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage < 1 ? 1 : widget.initialPage;
    _loadPdf();
    if (widget.trackProgress) {
      LibraryService.instance.recordAccess(widget.material);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logActivity('open');
    });
  }

  Future<void> _loadPdf() async {
    try {
      // Uses the downloaded copy when there is one, so this works offline.
      final bytes = await DownloadService.instance.loadPdf(widget.material);
      final document = await PdfDocument.openData(bytes);

      final pages = document.pagesCount;
      if (widget.trackProgress && widget.material.totalPages != pages) {
        await LibraryService.instance.setPageCount(widget.material, pages);
      }

      final first = await document.getPage(1);
      _pageAspect = first.width / first.height;
      await first.close();

      _bytes = bytes;
      _renderDocument = document;
      _pageCount = pages;
      _currentPage = _currentPage.clamp(1, pages);

      // The page the reader opens on counts as read too.
      if (widget.trackProgress) {
        widget.onProgressSaved(_currentPage);
        LibraryService.instance.saveProgress(widget.material, _currentPage);
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Renders one page as a PNG sized for this screen.
  Future<FlipbookPage> _renderPage(int pageNumber) {
    final completer = Completer<FlipbookPage>();
    final targetWidth = math.min(
      MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context),
      2000.0,
    );

    _renderLock = _renderLock.then((_) async {
      try {
        final page = await _renderDocument!.getPage(pageNumber);
        try {
          final scale = targetWidth / page.width;
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (image == null) throw Exception('Could not render page');
          completer
              .complete(FlipbookPage(image.bytes, page.width / page.height));
        } finally {
          await page.close();
        }
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<void> _logActivity(String action) async {
    if (widget.session == null) return;
    try {
      await ActivityService.logActivity(
        studentId: widget.session!.idNumber,
        studentName: widget.session!.fullName,
        department: widget.session!.department,
        materialTitle: widget.material.title,
        materialCode: widget.material.code,
        currentPage: _currentPage,
        totalPages: widget.material.totalPages,
        action: action,
      );
    } catch (_) {}
  }

  void _onPageChanged(int pageNumber) {
    if (_currentPage == pageNumber) return;
    setState(() => _currentPage = pageNumber);
    if (!widget.trackProgress) return;
    widget.onProgressSaved(pageNumber);
    // Save progress on the device so "Resume" works after a restart.
    LibraryService.instance.saveProgress(widget.material, pageNumber);
    if (pageNumber % 5 == 0) _logActivity('read');
  }

  Future<void> _toggleBookmark() async {
    final added = await LibraryService.instance
        .toggleBookmark(widget.material, _currentPage);
    setState(() {});
    // Logged so faculty can see bookmarked pages in Activity Logs.
    await _logActivity(added ? 'bookmark' : 'unbookmark');
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(added
            ? 'Bookmarked page $_currentPage'
            : 'Removed bookmark from page $_currentPage'),
      ));
  }

  void _toggleMode() {
    setState(() {
      if (_mode == ReaderMode.flipbook) {
        if (!_ownVerticalView) {
          _pinchDocument = PdfDocument.openData(_bytes!);
          _pinchController = PdfControllerPinch(
            document: _pinchDocument!,
            initialPage: _currentPage,
          );
        }
        _mode = ReaderMode.vertical;
      } else {
        _disposeVertical();
        _mode = ReaderMode.flipbook;
      }
    });
  }

  void _disposeVertical() {
    _pinchController?.dispose();
    _pinchController = null;
    _pinchDocument?.then((d) => d.close()).catchError((_) {});
    _pinchDocument = null;
  }

  void _previousPage() {
    if (_mode == ReaderMode.flipbook) {
      _flipbookKey.currentState?.flipPrevious();
    } else if (_ownVerticalView) {
      _verticalKey.currentState?.previousPage();
    } else {
      _pinchController?.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _nextPage() {
    if (_mode == ReaderMode.flipbook) {
      _flipbookKey.currentState?.flipNext();
    } else if (_ownVerticalView) {
      _verticalKey.currentState?.nextPage();
    } else {
      _pinchController?.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    // Where the student stopped, for the faculty's reading progress view.
    if (!_isLoading && _error == null) _logActivity('progress');
    _disposeVertical();
    final doc = _renderDocument;
    if (doc != null) _renderLock.then((_) => doc.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mat = widget.material;
    final isFlipbook = _mode == ReaderMode.flipbook;

    return Scaffold(
      backgroundColor: const Color(0xFF070D1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mat.code,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text(
              isFlipbook ? 'Flipbook' : 'Vertical Scroll',
              style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip:
                isFlipbook ? 'Switch to Vertical Scroll' : 'Switch to Flipbook',
            icon: Icon(
              isFlipbook ? Icons.swap_vert_rounded : Icons.auto_stories_rounded,
              color: Colors.white,
            ),
            onPressed: _isLoading || _error != null ? null : _toggleMode,
          ),
          if (widget.trackProgress)
            Builder(builder: (context) {
              final marked = LibraryService.instance
                  .isBookmarked(widget.material.id, _currentPage);
              return IconButton(
                tooltip: marked ? 'Remove bookmark' : 'Bookmark this page',
                icon: Icon(
                    marked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    color: marked ? const Color(0xFFFBBF24) : Colors.white),
                onPressed:
                    _isLoading || _error != null ? null : _toggleBookmark,
              );
            }),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
              )
            : _error != null
                ? _buildError(_error!)
                : _buildViewer(),
      ),
    );
  }

  Widget _buildViewer() {
    return Column(
      children: [
        LinearProgressIndicator(
          value: _pageCount == 0 ? 0 : _currentPage / _pageCount,
          backgroundColor: const Color(0xFF1E293B),
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
          minHeight: 4,
        ),
        Expanded(
          child: _mode == ReaderMode.flipbook
              ? FlipbookView(
                  key: _flipbookKey,
                  pageCount: _pageCount,
                  initialPage: _currentPage,
                  loadPage: _renderPage,
                  onPageChanged: _onPageChanged,
                )
              : _ownVerticalView
                  ? VerticalPagesView(
                      key: _verticalKey,
                      pageCount: _pageCount,
                      initialPage: _currentPage,
                      aspectRatio: _pageAspect,
                      loadPage: _renderPage,
                      onPageChanged: _onPageChanged,
                    )
                  : PdfViewPinch(
                      controller: _pinchController!,
                      onPageChanged: _onPageChanged,
                      backgroundDecoration:
                          const BoxDecoration(color: Color(0xFF070D1E)),
                      builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                        options: const DefaultBuilderOptions(),
                        documentLoaderBuilder: (_) => const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF38BDF8)),
                        ),
                        pageLoaderBuilder: (_) => const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF38BDF8)),
                        ),
                        errorBuilder: (_, error) =>
                            _buildError(error.toString()),
                      ),
                    ),
        ),
        _buildBottomControls(),
      ],
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            const Text(
              'Could not load PDF',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xFF0F172A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                size: 22, color: Colors.white),
            onPressed: _currentPage > 1 ? _previousPage : null,
          ),
          Text(
            'Page $_currentPage of $_pageCount',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded,
                size: 22, color: Colors.white),
            onPressed: _currentPage < _pageCount ? _nextPage : null,
          ),
        ],
      ),
    );
  }
}
