import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';

import '../models/learning_material.dart';
import '../models/user_session.dart';
import 'activity_service.dart';
import 'library_service.dart';
import 'notification_service.dart';

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

/// What a running task is doing right now.
enum DownloadPhase {
  /// Downloading the PDF from the server.
  fetching,

  /// Turning a PDF page into an image (single-page downloads).
  rendering,

  /// Writing the file to the phone.
  saving,
}

class DownloadTask {
  DownloadTask({required this.material, this.page});

  final LearningMaterial material;

  /// Null for the whole document, otherwise a single page number.
  final int? page;

  DownloadStatus status = DownloadStatus.queued;
  double? progress; // 0..1 across all phases, null when unknown
  String? error;

  DownloadPhase phase = DownloadPhase.fetching;

  /// Bytes done / total for the current phase. Total is null when the
  /// server doesn't say how big the file is.
  int receivedBytes = 0;
  int? totalBytes;
  double bytesPerSecond = 0;

  /// Size of the saved file once finished.
  int? savedBytes;

  DateTime _phaseStart = DateTime.now();

  Duration? get timeLeft {
    final total = totalBytes;
    if (total == null || bytesPerSecond <= 0) return null;
    final seconds = (total - receivedBytes) / bytesPerSecond;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  void _startPhase(DownloadPhase newPhase, {int? total}) {
    phase = newPhase;
    receivedBytes = 0;
    totalBytes = total;
    bytesPerSecond = 0;
    _phaseStart = DateTime.now();
  }

  void _updateBytes(int received) {
    receivedBytes = received;
    final elapsed = DateTime.now().difference(_phaseStart).inMicroseconds / 1e6;
    if (elapsed > 0.05) bytesPerSecond = received / elapsed;
  }

  bool get isFullDocument => page == null;
  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.downloading;
  bool get isFinished => !isActive;

  String get label => isFullDocument ? 'Full document' : 'Page $page';

  bool matches(String materialId, int? page) =>
      material.id == materialId && this.page == page;
}

/// Sequential download queue for whole documents and single pages.
class DownloadService extends ChangeNotifier {
  DownloadService._();
  static final DownloadService instance = DownloadService._();

  final List<DownloadTask> _tasks = [];
  bool _running = false;
  UserSession? _session;

  // Full PDF bytes kept in memory while pages are being downloaded or
  // read, so one PDF isn't fetched again for every page.
  final Map<String, Uint8List> _pdfCache = {};

  LibraryService get _library => LibraryService.instance;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get activeCount => _tasks.where((t) => t.isActive).length;

  void setSession(UserSession session) => _session = session;

  DownloadTask? activeTaskFor(String materialId, {int? page}) {
    for (final t in _tasks) {
      if (t.isActive && t.matches(materialId, page)) return t;
    }
    return null;
  }

  /// Returns false if it was already downloaded or already queued.
  bool enqueueFull(LearningMaterial material) {
    if (_library.entryFor(material.id)?.isFullyDownloaded == true) {
      return false;
    }
    return _enqueue(DownloadTask(material: material));
  }

  /// Returns false if it was already downloaded or already queued.
  bool enqueuePage(LearningMaterial material, int page) {
    if (_library.entryFor(material.id)?.isPageAvailable(page) == true) {
      return false;
    }
    return _enqueue(DownloadTask(material: material, page: page));
  }

  bool _enqueue(DownloadTask task) {
    if (activeTaskFor(task.material.id, page: task.page) != null) {
      return false;
    }
    _tasks.add(task);
    notifyListeners();
    _pump();
    return true;
  }

  void cancel(DownloadTask task) {
    if (!task.isActive) return;
    task.status = DownloadStatus.cancelled;
    notifyListeners();
  }

  void retry(DownloadTask task) {
    _tasks.remove(task);
    _enqueue(DownloadTask(material: task.material, page: task.page));
  }

  void clearFinished() {
    _tasks.removeWhere((t) => t.isFinished);
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next =
            _tasks.where((t) => t.status == DownloadStatus.queued).firstOrNull;
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _running = false;
      // Release memory once nothing else needs the cached PDFs.
      if (activeCount == 0) _pdfCache.clear();
    }
  }

  Future<void> _run(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    task.progress = 0;
    notifyListeners();

    try {
      final (bytes, fromNetwork) = await _fetchPdf(task);
      _throwIfCancelled(task);

      if (task.isFullDocument) {
        await _saveFull(task, bytes, fromNetwork: fromNetwork);
      } else {
        await _savePage(task, bytes, fromNetwork: fromNetwork);
      }
      _throwIfCancelled(task);

      task.status = DownloadStatus.completed;
      task.progress = 1;
      _logDownload(task);
    } catch (e) {
      if (task.status != DownloadStatus.cancelled) {
        task.status = DownloadStatus.failed;
        task.error = e.toString();
      }
    }
    notifyListeners();
  }

  /// PDF bytes for [material] from the device, the cache, or the network.
  /// Also used by the reader so an open document isn't downloaded twice.
  Future<Uint8List> loadPdf(LearningMaterial material) async {
    final local = await _library.readFullPdf(material.id);
    if (local != null) return local;

    final cached = _pdfCache[material.id];
    if (cached != null) return cached;

    final url = material.fileUrl;
    if (url == null || url.isEmpty) throw Exception('No PDF attached');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Download failed (HTTP ${response.statusCode})');
    }
    _cache(material.id, response.bodyBytes);
    return response.bodyBytes;
  }

  void _cache(String materialId, Uint8List bytes) {
    // PDFs can be large; keep at most two in memory.
    if (_pdfCache.length >= 2) _pdfCache.remove(_pdfCache.keys.first);
    _pdfCache[materialId] = bytes;
  }

  static void _throwIfCancelled(DownloadTask task) {
    if (task.status == DownloadStatus.cancelled) throw Exception('Cancelled');
  }

  /// Share of the progress bar used by the network download when the file
  /// still has to be prepared and saved afterwards.
  static double _fetchShare(DownloadTask task) =>
      task.isFullDocument ? 0.9 : 0.7;

  /// The PDF bytes, and whether they had to come from the network.
  Future<(Uint8List, bool)> _fetchPdf(DownloadTask task) async {
    final material = task.material;

    final local = await _library.readFullPdf(material.id);
    if (local != null) return (local, false);
    final cached = _pdfCache[material.id];
    if (cached != null) return (cached, false);

    final url = material.fileUrl;
    if (url == null || url.isEmpty) throw Exception('No PDF attached');

    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }

      final total = response.contentLength;
      task._startPhase(DownloadPhase.fetching,
          total: total != null && total > 0 ? total : null);
      notifyListeners();

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        _throwIfCancelled(task);
        builder.add(chunk);
        task._updateBytes(builder.length);
        final known = task.totalBytes;
        task.progress =
            known == null ? null : builder.length / known * _fetchShare(task);
        notifyListeners();
      }

      final bytes = builder.takeBytes();
      _cache(material.id, bytes);
      return (bytes, true);
    } finally {
      client.close();
    }
  }

  Future<void> _saveFull(DownloadTask task, Uint8List bytes,
      {required bool fromNetwork}) async {
    final material = task.material;
    final doc = await PdfDocument.openData(bytes);
    final pages = doc.pagesCount;
    await doc.close();

    final file = await _library.fullPdfFile(material.id);
    await _writeWithProgress(
      task,
      file,
      bytes,
      startProgress: fromNetwork ? _fetchShare(task) : 0,
      // Bytes already on the phone would otherwise finish instantly.
      minDuration:
          fromNetwork ? Duration.zero : const Duration(milliseconds: 1800),
    );

    await _library.setPageCount(material, pages);
    await _library.markFullDownloaded(material);
  }

  Future<void> _savePage(DownloadTask task, Uint8List bytes,
      {required bool fromNetwork}) async {
    final material = task.material;
    final pageNumber = task.page!;

    task._startPhase(DownloadPhase.rendering);
    notifyListeners();

    final doc = await PdfDocument.openData(bytes);
    final Uint8List imageBytes;
    try {
      if (pageNumber < 1 || pageNumber > doc.pagesCount) {
        throw Exception('Page $pageNumber does not exist');
      }
      final page = await doc.getPage(pageNumber);
      try {
        // Render at 2x for sharp text on phone screens.
        final image = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (image == null) throw Exception('Could not render page');
        imageBytes = image.bytes;
      } finally {
        await page.close();
      }
      if (material.totalPages == 0) {
        await _library.setPageCount(material, doc.pagesCount);
      }
    } finally {
      await doc.close();
    }
    _throwIfCancelled(task);

    final file = await _library.pageImageFile(material.id, pageNumber);
    await _writeWithProgress(
      task,
      file,
      imageBytes,
      startProgress: fromNetwork ? _fetchShare(task) : 0,
      minDuration: const Duration(milliseconds: 1500),
    );

    await _library.markPageDownloaded(material, pageNumber);
  }

  /// Writes [bytes] in chunks, updating the task's byte counts as it goes.
  /// Takes at least [minDuration] so the progress is visible.
  Future<void> _writeWithProgress(
    DownloadTask task,
    File file,
    Uint8List bytes, {
    required double startProgress,
    required Duration minDuration,
  }) async {
    const chunks = 30;
    final total = bytes.length;
    final chunkSize = total <= chunks ? 1 : (total / chunks).ceil();

    task._startPhase(DownloadPhase.saving, total: total);
    notifyListeners();

    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final stopwatch = Stopwatch()..start();
    var cancelled = false;
    try {
      for (var offset = 0; offset < total; offset += chunkSize) {
        if (task.status == DownloadStatus.cancelled) {
          cancelled = true;
          break;
        }

        final end = offset + chunkSize > total ? total : offset + chunkSize;
        sink.add(Uint8List.sublistView(bytes, offset, end));

        final wait = minDuration * (end / total) - stopwatch.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);

        task._updateBytes(end);
        task.progress = startProgress + (1 - startProgress) * end / total;
        notifyListeners();
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (cancelled) {
      if (await file.exists()) await file.delete();
      throw Exception('Cancelled');
    }
    task.savedBytes = total;
  }

  void _logDownload(DownloadTask task) {
    final session = _session;
    if (session == null) return;
    ActivityService.logActivity(
      studentId: session.idNumber,
      studentName: session.fullName,
      department: session.department,
      materialTitle: task.material.title,
      materialCode: task.material.code,
      currentPage: task.page ?? 0,
      totalPages: task.material.totalPages,
      action: 'download',
    );

    // Tell the uploader once per material, not for every single page.
    final pages = _library.entryFor(task.material.id)?.downloadedPages.length;
    final firstDownload = task.isFullDocument || (pages != null && pages <= 1);
    final uploader = task.material.uploadedBy;
    if (firstDownload && uploader != null) {
      NotificationService.notifyMany(
        to: [uploader],
        from: session.idNumber,
        title: 'Student Downloaded Your Material',
        body: '${session.fullName} (${session.idNumber}) downloaded '
            '${task.isFullDocument ? '' : 'pages of '}"${task.material.title}".',
        type: 'faculty_activity',
      );
    }
  }
}
