import 'dart:io';

import 'package:flutter/material.dart';
import '../models/learning_material.dart';
import '../services/library_service.dart';

/// Offline viewer for pages that were downloaded one at a time.
class DownloadedPagesViewer extends StatefulWidget {
  final LearningMaterial material;
  final List<int> pages; // sorted page numbers
  final int initialPage;

  const DownloadedPagesViewer({
    super.key,
    required this.material,
    required this.pages,
    required this.initialPage,
  });

  @override
  State<DownloadedPagesViewer> createState() => _DownloadedPagesViewerState();
}

class _DownloadedPagesViewerState extends State<DownloadedPagesViewer> {
  late final PageController _controller;
  late int _index;
  final Map<int, File> _files = {};

  @override
  void initState() {
    super.initState();
    final start = widget.pages.indexOf(widget.initialPage);
    _index = start < 0 ? 0 : start;
    _controller = PageController(initialPage: _index);
    _resolveFiles();
    LibraryService.instance.recordAccess(widget.material);
    _markRead(_index);
  }

  void _markRead(int index) => LibraryService.instance
      .saveProgress(widget.material, widget.pages[index]);

  Future<void> _resolveFiles() async {
    for (final page in widget.pages) {
      _files[page] =
          await LibraryService.instance.pageImageFile(widget.material.id, page);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages[_index];

    return Scaffold(
      backgroundColor: const Color(0xFF070D1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.material.code,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Text('Downloaded pages (${widget.pages.length})',
                style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8))),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.pages.length,
                onPageChanged: (i) {
                  setState(() => _index = i);
                  _markRead(i);
                },
                itemBuilder: (_, i) {
                  final file = _files[widget.pages[i]];
                  if (file == null) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF38BDF8)));
                  }
                  return InteractiveViewer(
                    maxScale: 4,
                    child: Center(
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                            'Page file is missing.',
                            style: TextStyle(color: Color(0xFF94A3B8))),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFF0F172A),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        size: 22, color: Colors.white),
                    onPressed: _index > 0
                        ? () => _controller.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut)
                        : null,
                  ),
                  Text(
                    widget.material.totalPages > 0
                        ? 'Page $page of ${widget.material.totalPages}'
                        : 'Page $page',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded,
                        size: 22, color: Colors.white),
                    onPressed: _index < widget.pages.length - 1
                        ? () => _controller.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
