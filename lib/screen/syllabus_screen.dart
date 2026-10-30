import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/learning_material.dart';
import '../models/syllabus_content.dart';
import '../models/user_session.dart';
import '../services/activity_service.dart';
import '../services/download_service.dart';
import '../services/library_service.dart';
import '../services/syllabus_text.dart';
import '../widgets/syllabus_content_view.dart';
import 'physical_flipbook_reader.dart';

/// A syllabus shown as readable text (headings and paragraphs), open to
/// every student - no permission and no download needed.
class SyllabusScreen extends StatefulWidget {
  final LearningMaterial material;
  final UserSession? session;

  const SyllabusScreen({super.key, required this.material, this.session});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  static const _accent = Color(0xFF38BDF8);
  static const _muted = Color(0xFF94A3B8);

  bool _loading = true;
  String? _error;
  List<SyllabusBlock> _blocks = const [];

  double _textScale = 1.0;
  bool _searching = false;
  final _search = TextEditingController();
  List<int> _matchBlocks = const []; // block index of each match
  int _currentMatch = 0;
  final Map<int, GlobalKey> _blockKeys = {};

  LibraryService get _library => LibraryService.instance;

  /// Course tables read from an older PDF syllabus, when it is a
  /// curriculum outline (the same reader as the editor's Fill from PDF).
  SyllabusContent? _fromPdf;

  /// Syllabi entered as content (courses by semester), or tables read
  /// from an older PDF one; other PDFs are shown as text.
  SyllabusContent? get _content => widget.material.syllabusContent ?? _fromPdf;

  @override
  void initState() {
    super.initState();
    _library.recordAccess(widget.material);
    _logOpen();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _logOpen() async {
    final s = widget.session;
    if (s == null) return;
    await ActivityService.logActivity(
      studentId: s.idNumber,
      studentName: s.fullName,
      department: s.department,
      materialTitle: widget.material.title,
      materialCode: widget.material.code,
      currentPage: 0,
      totalPages: widget.material.totalPages,
      action: 'open',
    );
  }

  Future<void> _load() async {
    if (_content != null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await DownloadService.instance.loadPdf(widget.material);
      // Reading the text can take a moment; keep the screen responsive.
      final lines = kIsWeb
          ? extractPdfLines(bytes)
          : await compute(extractPdfLines, bytes);
      final tables = SyllabusContent.fromPdfLines(lines);
      if (!mounted) return;
      setState(() {
        if (tables.courseCount >= 3) _fromPdf = tables;
        _blocks = buildSyllabusBlocks(lines);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open the syllabus. Check your internet '
            'connection and try again.';
      });
    }
  }

  void _onSearch(String query) {
    if (_content != null) {
      setState(() {}); // the course tables filter themselves
      return;
    }
    final q = query.trim().toLowerCase();
    final matches = <int>[];
    if (q.isNotEmpty) {
      for (var i = 0; i < _blocks.length; i++) {
        final text = _blocks[i].text.toLowerCase();
        var from = 0;
        while ((from = text.indexOf(q, from)) != -1) {
          matches.add(i);
          from += q.length;
        }
      }
    }
    setState(() {
      _matchBlocks = matches;
      _currentMatch = 0;
    });
    if (matches.isNotEmpty) _jumpTo(0);
  }

  void _jumpTo(int match) {
    setState(() => _currentMatch = match);
    final ctx = _blockKeys[_matchBlocks[match]]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.2);
    }
  }

  void _openAsDocument() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhysicalFlipbookReader(
          material: widget.material,
          initialPage: 1,
          onProgressSaved: (_) {},
          session: widget.session,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mat = widget.material;
    final isFavorite = _library.isFavorite(mat.id);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        iconTheme: const IconThemeData(color: Colors.white),
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onSearch,
                style: const TextStyle(color: Colors.white),
                cursorColor: _accent,
                decoration: const InputDecoration(
                  hintText: 'Search code or course title...',
                  hintStyle: TextStyle(color: _muted),
                  border: InputBorder.none,
                ),
              )
            : Text(mat.code,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search,
                color: Colors.white),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                _onSearch('');
              }
            },
          ),
          if (!_searching) ...[
            IconButton(
              tooltip: 'Smaller text',
              icon: const Icon(Icons.text_decrease, color: Colors.white),
              onPressed: _textScale > 0.8
                  ? () => setState(() => _textScale -= 0.1)
                  : null,
            ),
            IconButton(
              tooltip: 'Bigger text',
              icon: const Icon(Icons.text_increase, color: Colors.white),
              onPressed: _textScale < 1.8
                  ? () => setState(() => _textScale += 0.1)
                  : null,
            ),
            IconButton(
              tooltip: isFavorite ? 'Remove from library' : 'Save to library',
              icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? const Color(0xFFF43F5E) : Colors.white),
              onPressed: () async {
                await _library.toggleFavorite(mat);
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
        bottom: _searching && _search.text.trim().isNotEmpty && _content == null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: _buildSearchBar(),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildSearchBar() {
    final count = _matchBlocks.length;
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 40,
      child: Row(
        children: [
          Text(
            count == 0 ? 'No matches' : '${_currentMatch + 1} of $count',
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Previous',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            onPressed: count == 0
                ? null
                : () => _jumpTo((_currentMatch - 1 + count) % count),
          ),
          IconButton(
            tooltip: 'Next',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            onPressed:
                count == 0 ? null : () => _jumpTo((_currentMatch + 1) % count),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final content = _content;
    if (content != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: SyllabusContentView(
            content: content,
            header: _buildHeader(),
            query: _search.text,
            textScale: _textScale,
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _accent),
            SizedBox(height: 14),
            Text('Preparing the syllabus...', style: TextStyle(color: _muted)),
          ],
        ),
      );
    }
    if (_error != null) {
      return _message(Icons.wifi_off_rounded, _error!,
          action: TextButton(
            onPressed: _load,
            child: const Text('Try again', style: TextStyle(color: _accent)),
          ));
    }
    if (_blocks.isEmpty) {
      // Scanned (image-only) PDFs have no text to show.
      return _message(
        Icons.image_outlined,
        'This syllabus is a scanned copy, so it can\'t be shown as text.',
        action: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3A86FF),
              foregroundColor: Colors.white),
          onPressed: _openAsDocument,
          icon: const Icon(Icons.auto_stories_rounded, size: 18),
          label: const Text('View as document'),
        ),
      );
    }

    final query = _search.text.trim();
    final current = _matchBlocks.isEmpty ? -1 : _matchBlocks[_currentMatch];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              for (var i = 0; i < _blocks.length; i++)
                Padding(
                  key: _blockKeys.putIfAbsent(i, GlobalKey.new),
                  padding: EdgeInsets.only(
                      top: _blocks[i].isHeading && i > 0 ? 18 : 0,
                      bottom: _blocks[i].isHeading ? 6 : 10),
                  child: SelectableText.rich(
                    _highlighted(_blocks[i], query, i == current),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final mat = widget.material;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: mat.coverGradient),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('SYLLABUS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ),
          const SizedBox(height: 10),
          Text(mat.title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              _content != null
                  ? '${mat.code} • ${mat.program}'
                  : '${mat.code} • ${mat.program} • ${mat.year} • ${mat.term}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          Text('Instructor: ${mat.instructor}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ],
      ),
    );
  }

  /// The block's text with every search match highlighted.
  TextSpan _highlighted(SyllabusBlock block, String query, bool isCurrent) {
    final style = block.isHeading
        ? TextStyle(
            color: _accent,
            fontSize: 16.5 * _textScale,
            fontWeight: FontWeight.bold,
            height: 1.35)
        : TextStyle(
            color: const Color(0xFFE2E8F0),
            fontSize: 14.5 * _textScale,
            height: 1.6);

    if (query.isEmpty) return TextSpan(text: block.text, style: style);

    final spans = <TextSpan>[];
    final lower = block.text.toLowerCase();
    final q = query.toLowerCase();
    var start = 0;
    while (true) {
      final i = lower.indexOf(q, start);
      if (i == -1) break;
      if (i > start) spans.add(TextSpan(text: block.text.substring(start, i)));
      spans.add(TextSpan(
        text: block.text.substring(i, i + q.length),
        style: TextStyle(
          backgroundColor:
              isCurrent ? const Color(0xFFFBBF24) : const Color(0x88FBBF24),
          color: Colors.black,
        ),
      ));
      start = i + q.length;
    }
    if (start < block.text.length) {
      spans.add(TextSpan(text: block.text.substring(start)));
    }
    return TextSpan(style: style, children: spans);
  }

  Widget _message(IconData icon, String text, {Widget? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF64748B), size: 48),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted)),
              if (action != null) ...[const SizedBox(height: 14), action],
            ],
          ),
        ),
      );
}
