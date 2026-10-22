import 'package:flutter/material.dart';
import '../../services/download_service.dart';

/// "812.4 KB", "5.2 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String formatTimeLeft(Duration d) {
  if (d.inSeconds < 1) return 'less than a second left';
  if (d.inMinutes < 1) return '${d.inSeconds} s left';
  final seconds = d.inSeconds % 60;
  return '${d.inMinutes} min ${seconds.toString().padLeft(2, '0')} s left';
}

class DownloadQueueScreen extends StatelessWidget {
  const DownloadQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadService.instance;

    return ListenableBuilder(
      listenable: downloads,
      builder: (context, _) {
        final tasks = downloads.tasks;
        final active = tasks.where((t) => t.isActive).toList();
        final finished = tasks.where((t) => t.isFinished).toList().reversed;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF1C2541),
            title: const Text('Download Queue',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (finished.isNotEmpty)
                TextButton(
                  onPressed: downloads.clearFinished,
                  child: const Text('Clear finished',
                      style: TextStyle(color: Color(0xFF38BDF8))),
                ),
            ],
          ),
          body: tasks.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_done_rounded,
                            color: Color(0xFF64748B), size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No downloads yet.\nTap the download icon on a '
                          'material or a page to add it here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (active.isNotEmpty) ...[
                      _sectionTitle('In progress (${active.length})'),
                      ...active.map((t) => _TaskTile(task: t)),
                      const SizedBox(height: 12),
                    ],
                    if (finished.isNotEmpty) ...[
                      _sectionTitle('Finished'),
                      ...finished.map((t) => _TaskTile(task: t)),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadService.instance;

    final (IconData icon, Color color, String status) = switch (task.status) {
      DownloadStatus.queued => (
          Icons.schedule_rounded,
          const Color(0xFF94A3B8),
          'Waiting'
        ),
      DownloadStatus.downloading => (
          Icons.downloading_rounded,
          const Color(0xFF38BDF8),
          switch (task.phase) {
            DownloadPhase.fetching => 'Downloading',
            DownloadPhase.rendering => 'Preparing page',
            DownloadPhase.saving => 'Saving to phone',
          }
        ),
      DownloadStatus.completed => (
          Icons.check_circle_rounded,
          const Color(0xFF10B981),
          task.savedBytes == null
              ? 'Downloaded'
              : 'Downloaded • ${formatBytes(task.savedBytes!)}'
        ),
      DownloadStatus.failed => (
          Icons.error_outline_rounded,
          const Color(0xFFEF4444),
          'Failed'
        ),
      DownloadStatus.cancelled => (
          Icons.cancel_outlined,
          const Color(0xFF64748B),
          'Cancelled'
        ),
    };

    final downloading = task.status == DownloadStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.material.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text('${task.material.code} • ${task.label} • $status',
                        style: TextStyle(color: color, fontSize: 11.5)),
                  ],
                ),
              ),
              if (downloading && task.progress != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('${(task.progress! * 100).toInt()}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                ),
              if (task.isActive)
                IconButton(
                  tooltip: 'Cancel',
                  icon:
                      const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                  onPressed: () => downloads.cancel(task),
                )
              else if (task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.cancelled)
                IconButton(
                  tooltip: 'Retry',
                  icon: const Icon(Icons.refresh_rounded,
                      color: Color(0xFF38BDF8)),
                  onPressed: () => downloads.retry(task),
                ),
            ],
          ),
          if (downloading) ...[
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              // Glides between updates instead of jumping.
              tween: Tween(end: task.progress ?? 0),
              duration: const Duration(milliseconds: 200),
              builder: (context, value, _) => LinearProgressIndicator(
                value: task.progress == null ? null : value,
                backgroundColor: const Color(0xFF0B132B),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
            _buildByteLine(),
          ],
          if (task.status == DownloadStatus.failed && task.error != null) ...[
            const SizedBox(height: 6),
            Text(task.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
          ],
        ],
      ),
    );
  }

  /// "245.3 KB / 812.0 KB        1.2 MB/s • 2 s left"
  Widget _buildByteLine() {
    const style = TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5);

    if (task.phase == DownloadPhase.rendering) {
      return const Text('Creating page image...', style: style);
    }

    final total = task.totalBytes;
    final sizes = total == null
        ? '${formatBytes(task.receivedBytes)} downloaded'
        : '${formatBytes(task.receivedBytes)} / ${formatBytes(total)}';

    final timeLeft = task.timeLeft;
    final speed = task.bytesPerSecond > 0
        ? '${formatBytes(task.bytesPerSecond.round())}/s'
        : null;
    final rate = [
      if (speed != null) speed,
      if (timeLeft != null) formatTimeLeft(timeLeft),
    ].join(' • ');

    return Row(
      children: [
        Expanded(child: Text(sizes, style: style)),
        if (rate.isNotEmpty) Text(rate, style: style),
      ],
    );
  }
}
