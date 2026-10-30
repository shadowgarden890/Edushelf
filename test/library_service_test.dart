import 'dart:io';

import 'package:edushelf_reading_application/models/learning_material.dart';
import 'package:edushelf_reading_application/services/library_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LearningMaterial _material(String id, {bool syllabus = false}) =>
    LearningMaterial.fromRow({
      'id': id,
      'code': 'ITP411',
      'title': 'Competency Appraisal $id',
      'program': 'BSIT',
      'year': '4th Year',
      'term': '1st Sem',
      'instructor': 'Juan Dela Cruz',
      'type': syllabus ? 'syllabus' : 'learning_material',
      'file_url': 'https://example.com/$id.pdf',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = LibraryService.instance;

  // Downloads are deleted from the app documents folder; use a temp one.
  final docs = Directory.systemTemp.createTempSync('edushelf_test');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => docs.path);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Switch away and back so each test starts from empty storage.
    await library.load('setup');
    await library.load('IT-23-01003');
  });

  test('library starts empty', () {
    expect(library.entries, isEmpty);
  });

  test('heart adds to and removes from the library', () async {
    final m = _material('a');

    await library.toggleFavorite(m);
    expect(library.isFavorite('a'), isTrue);
    expect(library.entries.map((e) => e.material.id), ['a']);

    await library.toggleFavorite(m);
    expect(library.isFavorite('a'), isFalse);
    expect(library.entries, isEmpty);
  });

  test('downloads appear in My Library and in History', () async {
    final m = _material('b');

    await library.markPageDownloaded(m, 3);
    final entry = library.entryFor('b')!;
    expect(library.entries.map((e) => e.material.id), ['b']);
    expect(library.history.map((e) => e.material.id), ['b']);
    expect(entry.isFavorite, isTrue, reason: 'downloading hearts it');
    expect(entry.isPageAvailable(3), isTrue);
    expect(entry.isPageAvailable(4), isFalse);
    expect(entry.isFullyDownloaded, isFalse);
  });

  test('bookmarks toggle on and off and are saved', () async {
    final m = _material('bm');

    expect(await library.toggleBookmark(m, 7), isTrue);
    expect(await library.toggleBookmark(m, 12), isTrue);
    expect(library.isBookmarked('bm', 7), isTrue);
    expect(await library.toggleBookmark(m, 7), isFalse);
    expect(library.entryFor('bm')!.bookmarks, {12});

    await library.load('IT-23-99999');
    await library.load('IT-23-01003');
    expect(library.entryFor('bm')!.bookmarks, {12});
  });

  test('reading progress survives reloads', () async {
    final m = _material('prog')..totalPages = 30;
    await library.saveProgress(m, 17);

    await library.load('IT-23-99999');
    await library.load('IT-23-01003');
    expect(library.entryFor('prog')!.material.currentPage, 17);
    expect(library.entryFor('prog')!.material.readPages, {17});
    expect(library.entries, isEmpty,
        reason: 'reading alone does not add it to My Library');
  });

  test('only pages actually opened count as read', () async {
    final m = _material('skip')..totalPages = 32;

    // Jump straight to the last page: only that page is read.
    await library.saveProgress(m, 32);
    expect(m.readPages, {32});

    // Jump to 31, then turn to 32: pages 1-30 stay unread.
    await library.saveProgress(m, 31);
    await library.saveProgress(m, 32);
    expect(m.readPages, {31, 32});
    expect(m.currentPage, 32);
    expect(m.progressPercent, 6); // 2 of 32 pages

    await library.load('IT-23-99999');
    await library.load('IT-23-01003');
    expect(library.entryFor('skip')!.material.readPages, {31, 32});
  });

  test('deleting downloads resets progress and bookmarks', () async {
    final m = _material('redo')..totalPages = 5;
    await library.markFullDownloaded(m);
    for (var p = 1; p <= 5; p++) {
      await library.saveProgress(m, p);
    }
    await library.toggleBookmark(m, 3);

    await library.deleteDownloads('redo');
    await library.markFullDownloaded(m); // downloaded again

    final saved = library.entryFor('redo')!;
    expect(saved.material.readPages, isEmpty);
    expect(saved.material.currentPage, 0);
    expect(saved.bookmarks, isEmpty);
  });

  test('History lists the most recently opened first', () async {
    await library.recordAccess(_material('old'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await library.recordAccess(_material('new'));

    expect(library.history.map((e) => e.material.id), ['new', 'old']);
    expect(library.entries, isEmpty);
  });

  test('a full download makes every page available', () async {
    final m = _material('c');

    await library.markFullDownloaded(m);
    final entry = library.entryFor('c')!;
    expect(entry.isPageAvailable(1), isTrue);
    expect(entry.isPageAvailable(250), isTrue);
  });

  test('downloading saves to My Library; un-hearting keeps the download',
      () async {
    final m = _material('d');

    await library.markPageDownloaded(m, 1);
    expect(library.isFavorite('d'), isTrue, reason: 'download hearts it');
    expect(library.entries.map((e) => e.material.id), ['d']);

    await library.toggleFavorite(m);
    expect(library.entries, isEmpty, reason: 'gone from My Library');
    expect(library.entryFor('d')!.isPageAvailable(1), isTrue,
        reason: 'the download stays on the device');
    expect(library.history.map((e) => e.material.id), ['d']);

    // More downloads later don't put the heart back.
    await library.markPageDownloaded(m, 2);
    expect(library.isFavorite('d'), isFalse);
  });

  test(
      'a hearted material without downloads leaves My Library when '
      'un-hearted', () async {
    final m = _material('h');
    await library.toggleFavorite(m);
    expect(library.entries.map((e) => e.material.id), ['h']);
    await library.toggleFavorite(m);
    expect(library.entries, isEmpty);
  });

  test('library is saved per student and survives reloads', () async {
    await library.toggleFavorite(_material('e'));
    await library.setPageCount(library.entryFor('e')!.material, 42);

    await library.load('IT-23-99999');
    expect(library.entries, isEmpty, reason: 'other students see nothing');

    await library.load('IT-23-01003');
    final entry = library.entryFor('e')!;
    expect(entry.isFavorite, isTrue);
    expect(entry.material.totalPages, 42);
    expect(entry.material.title, 'Competency Appraisal e');
  });

  test('LearningMaterial JSON round-trip keeps all fields', () {
    final m = _material('f', syllabus: true)..totalPages = 12;
    final copy = LearningMaterial.fromJson(m.toJson());

    expect(copy.toJson(), m.toJson());
    expect(copy.isSyllabus, isTrue);
    expect(copy.coverGradient, m.coverGradient);
  });
}
