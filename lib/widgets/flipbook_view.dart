import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A rendered page image and its width / height ratio.
class FlipbookPage {
  const FlipbookPage(this.bytes, this.aspectRatio);

  final Uint8List bytes;
  final double aspectRatio;
}

/// Book-style reader: pages turn in 3D around the left edge (the spine).
/// Drag horizontally to turn a page, or tap the left / right side.
class FlipbookView extends StatefulWidget {
  const FlipbookView({
    super.key,
    required this.pageCount,
    required this.initialPage,
    required this.loadPage,
    required this.onPageChanged,
  });

  final int pageCount;
  final int initialPage; // 1-based
  final Future<FlipbookPage> Function(int page) loadPage;
  final ValueChanged<int> onPageChanged;

  @override
  State<FlipbookView> createState() => FlipbookViewState();
}

class FlipbookViewState extends State<FlipbookView>
    with SingleTickerProviderStateMixin {
  static const _turnDuration = Duration(milliseconds: 450);
  static const _keepAround = 3; // pages cached on each side

  late int _page;
  late final AnimationController _turn;

  /// 1 = turning forward, -1 = turning back, 0 = idle.
  int _direction = 0;
  double _dragWidth = 1;

  final Map<int, FlipbookPage> _pages = {};
  final Set<int> _loading = {};
  final Set<int> _failed = {};

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(1, widget.pageCount);
    _turn = AnimationController(vsync: this, duration: _turnDuration);
    _prefetch();
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  int get page => _page;

  bool get _isTurning => _direction != 0;

  // ================================================
  // PAGE LOADING
  // ================================================
  void _prefetch() {
    for (final p in [_page, _page + 1, _page - 1, _page + 2]) {
      _ensureLoaded(p);
    }
    _pages.removeWhere((p, _) => (p - _page).abs() > _keepAround);
  }

  Future<void> _ensureLoaded(int p) async {
    if (p < 1 || p > widget.pageCount) return;
    if (_pages.containsKey(p) || _loading.contains(p)) return;

    _loading.add(p);
    _failed.remove(p);
    try {
      final page = await widget.loadPage(p);
      if (!mounted) return;
      setState(() => _pages[p] = page);
    } catch (_) {
      if (mounted) setState(() => _failed.add(p));
    } finally {
      _loading.remove(p);
    }
  }

  // ================================================
  // TURNING
  // ================================================
  Future<void> flipNext() => _animateTurn(1);

  Future<void> flipPrevious() => _animateTurn(-1);

  Future<void> _animateTurn(int direction) async {
    if (_isTurning || !_canTurn(direction)) return;
    setState(() => _direction = direction);
    _turn.value = 0;
    await _turn.animateTo(1, curve: Curves.easeInOut);
    _commitTurn();
  }

  bool _canTurn(int direction) =>
      direction > 0 ? _page < widget.pageCount : _page > 1;

  void _commitTurn() {
    setState(() {
      _page += _direction;
      _direction = 0;
      _turn.value = 0;
    });
    _prefetch();
    widget.onPageChanged(_page);
  }

  void _onDragStart(DragStartDetails details) {
    if (_turn.isAnimating) return;
    _direction = 0;
    _turn.value = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_turn.isAnimating) return;
    final dx = details.primaryDelta ?? 0;

    if (_direction == 0) {
      final direction = dx < 0 ? 1 : -1;
      if (dx == 0 || !_canTurn(direction)) return;
      setState(() => _direction = direction);
    }

    // Dragging left turns forward, dragging right turns back.
    _turn.value = (_turn.value - _direction * dx / _dragWidth).clamp(0.0, 1.0);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (!_isTurning || _turn.isAnimating) return;

    final velocity = details.primaryVelocity ?? 0;
    final flung = -_direction * velocity > 600;
    final completes =
        flung || (_turn.value > 0.35 && -_direction * velocity > -300);

    if (completes) {
      await _turn.animateTo(1, curve: Curves.easeOut);
      _commitTurn();
    } else {
      await _turn.animateBack(0, curve: Curves.easeOut);
      setState(() => _direction = 0);
    }
  }

  void _onTapUp(TapUpDetails details) {
    final x = details.localPosition.dx;
    if (x > _dragWidth * 0.66) {
      flipNext();
    } else if (x < _dragWidth * 0.33) {
      flipPrevious();
    }
  }

  // ================================================
  // BUILD
  // ================================================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _dragWidth = constraints.maxWidth;
        final pageSize = _pageSize(constraints);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onTapUp: _onTapUp,
          child: Center(
            child: SizedBox.fromSize(
              size: pageSize,
              child: AnimatedBuilder(
                animation: _turn,
                builder: (context, _) => _buildBook(pageSize),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The largest page that fits, using the current page's proportions.
  Size _pageSize(BoxConstraints c) {
    const margin = 16.0;
    final maxW = c.maxWidth - margin * 2;
    final maxH = c.maxHeight - margin * 2;
    final aspect = _pages[_page]?.aspectRatio ?? (1 / math.sqrt2);

    var w = maxW;
    var h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
    return Size(w, h);
  }

  Widget _buildBook(Size size) {
    final t = _turn.value;

    if (_direction > 0) {
      // Current page lifts off and turns over, revealing the next one.
      return Stack(
        fit: StackFit.expand,
        children: [
          _shaded(_pageFace(_page + 1), 0.35 * (1 - t)),
          _turning(_pageFace(_page), t, size),
        ],
      );
    }
    if (_direction < 0) {
      // Previous page turns back down over the current one.
      return Stack(
        fit: StackFit.expand,
        children: [
          _shaded(_pageFace(_page), 0.35 * t),
          _turning(_pageFace(_page - 1), 1 - t, size),
        ],
      );
    }
    return _pageFace(_page);
  }

  /// [t] = 0 lies flat, 1 = standing on its edge at the spine.
  Widget _turning(Widget face, double t, Size size) {
    final angle = t * math.pi / 2;
    final transform = Matrix4.identity()
      // Perspective scaled to page width so wide screens don't distort.
      ..setEntry(3, 2, 0.6 / size.width)
      ..rotateY(angle);

    return Transform(
      alignment: Alignment.centerLeft,
      transform: transform,
      child: Stack(
        fit: StackFit.expand,
        children: [
          face,
          // Darkens and adds a curl highlight as the page turns away.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.05 + 0.25 * t),
                    Colors.black.withValues(alpha: 0.45 * t),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shaded(Widget child, double amount) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: ColoredBox(color: Colors.black.withValues(alpha: amount)),
        ),
      ],
    );
  }

  Widget _pageFace(int p) {
    final page = _pages[p];

    Widget content;
    if (page != null) {
      content = Image.memory(
        page.bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    } else if (_failed.contains(p)) {
      content = Center(
        child: TextButton.icon(
          onPressed: () => _ensureLoaded(p),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Could not load page. Tap to retry'),
        ),
      );
    } else {
      _ensureLoaded(p);
      content = const Center(
        child:
            CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
            offset: const Offset(4, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          // Spine shadow along the left edge.
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 18,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x40000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
