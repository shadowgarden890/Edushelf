import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'flipbook_view.dart';

/// Continuous vertical scroll built from rendered page images. Used on
/// desktop, where pdfx's own scroll view only shows a gray area.
/// Every page gets the first page's shape, so jumps and the current page
/// can be worked out from the scroll position.
class VerticalPagesView extends StatefulWidget {
  const VerticalPagesView({
    super.key,
    required this.pageCount,
    required this.initialPage,
    required this.aspectRatio,
    required this.loadPage,
    required this.onPageChanged,
  });

  final int pageCount;
  final int initialPage;

  /// Page width / height.
  final double aspectRatio;
  final Future<FlipbookPage> Function(int page) loadPage;
  final ValueChanged<int> onPageChanged;

  @override
  State<VerticalPagesView> createState() => VerticalPagesViewState();
}

class VerticalPagesViewState extends State<VerticalPagesView> {
  static const _gap = 16.0;
  static const _maxPageWidth = 900.0;

  /// Pages kept rendered on each side of the current one.
  static const _keep = 4;

  ScrollController? _controller;
  double _extent = 0;
  late int _page = widget.initialPage;
  final Map<int, Future<FlipbookPage>> _cache = {};

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<FlipbookPage> _pageImage(int page) =>
      _cache.putIfAbsent(page, () => widget.loadPage(page));

  void _onScroll() {
    final c = _controller!;
    final middle = c.offset + c.position.viewportDimension / 2;
    // At the very bottom the last page counts as open, even if it never
    // reaches the middle of the window.
    final page = c.offset >= c.position.maxScrollExtent - 1
        ? widget.pageCount
        : (middle / _extent).floor().clamp(0, widget.pageCount - 1) + 1;
    if (page == _page) return;
    _page = page;
    _cache.removeWhere((p, _) => (p - page).abs() > _keep);
    widget.onPageChanged(page);
  }

  void _animateTo(int page) {
    final c = _controller;
    if (c == null || !c.hasClients) return;
    c.animateTo(
      ((page - 1) * _extent).clamp(0.0, c.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void nextPage() => _animateTo(math.min(_page + 1, widget.pageCount));
  void previousPage() => _animateTo(math.max(_page - 1, 1));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final pageWidth = math.min(constraints.maxWidth - 32, _maxPageWidth);
      final pageHeight = pageWidth / widget.aspectRatio;
      _extent = pageHeight + _gap;

      _controller ??= ScrollController(
          initialScrollOffset: (widget.initialPage - 1) * _extent)
        ..addListener(_onScroll);

      return Scrollbar(
        controller: _controller,
        child: ListView.builder(
          controller: _controller,
          itemCount: widget.pageCount,
          itemExtent: _extent,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(top: _gap),
            child: Center(
              child: SizedBox(
                width: pageWidth,
                height: pageHeight,
                child: _buildPage(index + 1),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPage(int page) {
    return FutureBuilder<FlipbookPage>(
      future: _pageImage(page),
      builder: (context, snap) {
        if (snap.hasError) {
          return Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: Text('Could not show page $page',
                style: const TextStyle(color: Colors.black54)),
          );
        }
        if (!snap.hasData) {
          return Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: Color(0xFF38BDF8)),
          );
        }
        return Image.memory(snap.data!.bytes,
            fit: BoxFit.contain, gaplessPlayback: true);
      },
    );
  }
}
