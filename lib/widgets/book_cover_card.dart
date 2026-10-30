import 'package:flutter/material.dart';
import '../models/learning_material.dart';

enum CoverDownloadState { none, partial, inProgress, full }

class BookCoverCard extends StatelessWidget {
  final LearningMaterial material;
  final VoidCallback onTap;

  /// Heart and download buttons are shown only when their callbacks are set.
  final bool isFavorite;
  final VoidCallback? onFavoriteTap;
  final CoverDownloadState downloadState;
  final VoidCallback? onDownloadTap;

  const BookCoverCard({
    super.key,
    required this.material,
    required this.onTap,
    this.isFavorite = false,
    this.onFavoriteTap,
    this.downloadState = CoverDownloadState.none,
    this.onDownloadTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: material.coverGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color:
                          material.coverGradient.first.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Spine shadow
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            bottomLeft: Radius.circular(14),
                          ),
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  material.program,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (material.isSyllabus)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFBBF24)
                                        .withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'SYLLABUS',
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                )
                              else
                                const Icon(Icons.menu_book_rounded,
                                    color: Colors.white70, size: 16),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            material.code,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            material.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                height: 1.2),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (material.totalPages > 0) ...[
                                const Icon(Icons.description_outlined,
                                    color: Colors.white60, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  '${material.totalPages} Pages',
                                  style: const TextStyle(
                                      color: Colors.white60, fontSize: 10),
                                ),
                              ],
                              const Spacer(),
                              if (onFavoriteTap != null)
                                _CoverAction(
                                  tooltip: isFavorite
                                      ? 'Remove from library'
                                      : 'Save to library',
                                  onTap: onFavoriteTap!,
                                  child: Icon(
                                    isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 16,
                                    color: isFavorite
                                        ? const Color(0xFFF43F5E)
                                        : Colors.white,
                                  ),
                                ),
                              if (onDownloadTap != null) ...[
                                const SizedBox(width: 6),
                                _CoverAction(
                                  tooltip: _downloadTooltip,
                                  onTap: onDownloadTap!,
                                  child: _downloadIcon,
                                ),
                              ],
                              if (onFavoriteTap == null &&
                                  onDownloadTap == null &&
                                  material.hasFile)
                                const Icon(Icons.picture_as_pdf,
                                    color: Colors.white70, size: 12),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Progress bar
                    if (material.readPages.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(14)),
                          child: LinearProgressIndicator(
                            value: material.progress,
                            backgroundColor: Colors.black26,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF38BDF8)),
                            minHeight: 4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              material.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5),
            ),
            Text(
              material.readPages.isEmpty
                  ? 'Unread'
                  : '${material.readPages.length} / ${material.totalPages} pages read (${material.progressPercent}%)',
              style: TextStyle(
                color: material.readPages.isEmpty
                    ? const Color(0xFF64748B)
                    : const Color(0xFF38BDF8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _downloadTooltip => switch (downloadState) {
        CoverDownloadState.full => 'Downloaded',
        CoverDownloadState.inProgress => 'Downloading...',
        CoverDownloadState.partial => 'Download remaining pages',
        CoverDownloadState.none => 'Download',
      };

  Widget get _downloadIcon => switch (downloadState) {
        CoverDownloadState.full => const Icon(Icons.download_done_rounded,
            size: 16, color: Color(0xFF34D399)),
        CoverDownloadState.inProgress => const SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        CoverDownloadState.partial =>
          const Icon(Icons.downloading_rounded, size: 16, color: Colors.white),
        CoverDownloadState.none =>
          const Icon(Icons.download_rounded, size: 16, color: Colors.white),
      };
}

class _CoverAction extends StatelessWidget {
  const _CoverAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
