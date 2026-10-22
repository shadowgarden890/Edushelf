import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/learning_material.dart';

/// What the student has done with one material: downloaded it or saved
/// it with the heart (My Library), opened it (History), bookmarks and
/// reading progress.
class LibraryEntry {
  LibraryEntry({
    required this.material,
    this.isFavorite = false,
    this.isFullyDownloaded = false,
    Set<int>? downloadedPages,
    Set<int>? bookmarks,
    this.favoritedAt,
    this.downloadedAt,
    this.lastAccessedAt,
  })  : downloadedPages = downloadedPages ?? <int>{},
        bookmarks = bookmarks ?? <int>{};

  final LearningMaterial material;
  bool isFavorite;
  bool isFullyDownloaded;
  final Set<int> downloadedPages;

  /// Bookmarked page numbers.
  final Set<int> bookmarks;

  DateTime? favoritedAt;
  DateTime? downloadedAt;

  /// Last time it was opened in a reader or downloaded.
  DateTime? lastAccessedAt;

  bool get hasDownloads => isFullyDownloaded || downloadedPages.isNotEmpty;

  /// My Library: everything downloaded, plus materials saved with the heart.
  bool get isInLibrary => isFavorite || hasDownloads;

  bool get isInHistory => lastAccessedAt != null || hasDownloads;

  /// When it was added to My Library (for sorting).
  DateTime? get addedAt {
    final times = [favoritedAt, downloadedAt].whereType<DateTime>().toList()
      ..sort();
    return times.isEmpty ? null : times.last;
  }

  bool get _isEmpty =>
      !isInLibrary &&
      !isInHistory &&
      bookmarks.isEmpty &&
      material.currentPage == 0;

  bool isPageAvailable(int page) =>
      isFullyDownloaded || downloadedPages.contains(page);

  Map<String, dynamic> toJson() => {
        'material': material.toJson(),
        'isFavorite': isFavorite,
        'isFullyDownloaded': isFullyDownloaded,
        'downloadedPages': downloadedPages.toList()..sort(),
        'bookmarks': bookmarks.toList()..sort(),
        'favoritedAt': favoritedAt?.toIso8601String(),
        'downloadedAt': downloadedAt?.toIso8601String(),
        'lastAccessedAt': lastAccessedAt?.toIso8601String(),
      };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => DateTime.tryParse(json[key] as String? ?? '');
    Set<int> ints(String key) => (json[key] as List? ?? []).cast<int>().toSet();

    return LibraryEntry(
      material:
          LearningMaterial.fromJson(json['material'] as Map<String, dynamic>),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isFullyDownloaded: json['isFullyDownloaded'] as bool? ?? false,
      downloadedPages: ints('downloadedPages'),
      bookmarks: ints('bookmarks'),
      favoritedAt: time('favoritedAt'),
      // Older saves had no download time; fall back to last access.
      downloadedAt: time('downloadedAt') ?? time('lastAccessedAt'),
      lastAccessedAt: time('lastAccessedAt'),
    );
  }
}

/// The signed-in student's library, kept on the device so it works offline.
/// Files live in `<app documents>/edushelf/<student id>/<material id>/`.
class LibraryService extends ChangeNotifier {
  LibraryService._();
  static final LibraryService instance = LibraryService._();

  String? _studentId;
  final Map<String, LibraryEntry> _entries = {};

  String get _prefsKey => 'library_$_studentId';

  /// Downloads need a filesystem, which the web build doesn't have.
  static bool get supportsDownloads => !kIsWeb;

  Future<void> load(String studentId) async {
    if (_studentId == studentId) return;
    _studentId = studentId;
    _entries.clear();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in map.entries) {
        _entries[e.key] =
            LibraryEntry.fromJson(e.value as Map<String, dynamic>);
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (_studentId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_entries.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// My Library: downloaded and hearted materials, newest first.
  List<LibraryEntry> get entries =>
      _sorted(_entries.values.where((e) => e.isInLibrary), (e) => e.addedAt);

  /// History: opened or downloaded materials, most recent first.
  List<LibraryEntry> get history => _sorted(
      _entries.values.where((e) => e.isInHistory), (e) => e.lastAccessedAt);

  static List<LibraryEntry> _sorted(
      Iterable<LibraryEntry> entries, DateTime? Function(LibraryEntry) key) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return entries.toList()
      ..sort((a, b) => (key(b) ?? epoch).compareTo(key(a) ?? epoch));
  }

  LibraryEntry? entryFor(String materialId) => _entries[materialId];

  bool isFavorite(String materialId) =>
      _entries[materialId]?.isFavorite ?? false;

  LibraryEntry _ensureEntry(LearningMaterial material) =>
      _entries.putIfAbsent(material.id, () => LibraryEntry(material: material));

  Future<void> toggleFavorite(LearningMaterial material) =>
      setFavorite(material, !isFavorite(material.id));

  Future<void> setFavorite(LearningMaterial material, bool favorite) async {
    final entry = _ensureEntry(material);
    entry.isFavorite = favorite;
    entry.favoritedAt = favorite ? DateTime.now() : null;
    _dropIfEmpty(material.id);
    notifyListeners();
    await _save();
  }

  /// Saves where the student stopped reading (survives app restarts).
  Future<void> saveProgress(LearningMaterial material, int page) async {
    material.currentPage = page;
    _ensureEntry(material).material.currentPage = page;
    notifyListeners();
    await _save();
  }

  bool isBookmarked(String materialId, int page) =>
      _entries[materialId]?.bookmarks.contains(page) ?? false;

  /// Adds or removes a bookmark; returns true when the page is now
  /// bookmarked.
  Future<bool> toggleBookmark(LearningMaterial material, int page) async {
    final bookmarks = _ensureEntry(material).bookmarks;
    final added = bookmarks.add(page);
    if (!added) bookmarks.remove(page);
    _dropIfEmpty(material.id);
    notifyListeners();
    await _save();
    return added;
  }

  /// Puts the material at the top of History.
  Future<void> recordAccess(LearningMaterial material) async {
    _ensureEntry(material).lastAccessedAt = DateTime.now();
    notifyListeners();
    await _save();
  }

  /// Remember the real page count once a PDF has been opened.
  Future<void> setPageCount(LearningMaterial material, int pages) async {
    material.totalPages = pages;
    final entry = _entries[material.id];
    if (entry == null) return;
    entry.material.totalPages = pages;
    notifyListeners();
    await _save();
  }

  Future<void> markFullDownloaded(LearningMaterial material) async {
    final now = DateTime.now();
    _ensureEntry(material)
      ..isFullyDownloaded = true
      ..downloadedAt = now
      ..lastAccessedAt = now;
    notifyListeners();
    await _save();
  }

  Future<void> markPageDownloaded(LearningMaterial material, int page) async {
    final now = DateTime.now();
    _ensureEntry(material)
      ..downloadedPages.add(page)
      ..downloadedAt = now
      ..lastAccessedAt = now;
    notifyListeners();
    await _save();
  }

  Future<void> deleteDownloads(String materialId) async {
    final entry = _entries[materialId];
    if (entry == null) return;

    final dir = await materialDir(materialId);
    if (await dir.exists()) await dir.delete(recursive: true);

    entry.isFullyDownloaded = false;
    entry.downloadedPages.clear();
    _dropIfEmpty(materialId);
    notifyListeners();
    await _save();
  }

  void _dropIfEmpty(String materialId) {
    if (_entries[materialId]?._isEmpty == true) {
      _entries.remove(materialId);
    }
  }

  // ================================================
  // FILES
  // ================================================
  Future<Directory> materialDir(String materialId) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(
        '${docs.path}/edushelf/$_studentId/${_safeName(materialId)}');
  }

  Future<File> fullPdfFile(String materialId) async =>
      File('${(await materialDir(materialId)).path}/full.pdf');

  Future<File> pageImageFile(String materialId, int page) async =>
      File('${(await materialDir(materialId)).path}/page_$page.png');

  /// The downloaded PDF's bytes, or null if it isn't downloaded.
  Future<Uint8List?> readFullPdf(String materialId) async {
    if (!supportsDownloads) return null;
    if (_entries[materialId]?.isFullyDownloaded != true) return null;
    final file = await fullPdfFile(materialId);
    return await file.exists() ? file.readAsBytes() : null;
  }

  static String _safeName(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
}
