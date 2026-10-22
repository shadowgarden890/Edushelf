import 'package:edushelf_reading_application/screen/teachers/teacher_activity_logs_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _log(
        String student, String title, String action, int page, int minute) =>
    {
      'student_id': student,
      'student_name': 'Student $student',
      'material_title': title,
      'material_code': 'IT 101',
      'action': action,
      'current_page': page,
      'total_pages': 40,
      'created_at': DateTime.utc(2026, 10, 21, 8, minute).toIso8601String(),
    };

void main() {
  test('summarizes progress, bookmarks and access per student', () {
    // Deliberately out of order: the stream gives newest first.
    final students = StudentActivity.group([
      _log('A', 'Book 1', 'progress', 22, 9),
      _log('A', 'Book 1', 'unbookmark', 5, 8),
      _log('A', 'Book 1', 'bookmark', 12, 7),
      _log('A', 'Book 1', 'bookmark', 5, 6),
      _log('A', 'Book 1', 'read', 10, 5),
      _log('A', 'Book 1', 'open', 1, 4),
      _log('A', 'Book 2', 'download', 0, 3),
      _log('A', 'Book 1', 'open', 1, 2),
      _log('B', 'Book 1', 'open', 1, 1),
    ]);

    expect(students.map((s) => s.studentId), ['A', 'B'],
        reason: 'most recently active first');

    final a = students.first;
    expect(a.name, 'Student A');
    final book1 = a.materials.firstWhere((m) => m.title == 'Book 1');
    expect(book1.lastPage, 22);
    expect(book1.totalPages, 40);
    expect(book1.progress, closeTo(0.55, 0.001));
    expect(book1.bookmarks, {12}, reason: 'page 5 was un-bookmarked');
    expect(book1.opens, 2);

    final book2 = a.materials.firstWhere((m) => m.title == 'Book 2');
    expect(book2.downloads, 1);
    expect(a.materials.first.title, 'Book 1',
        reason: 'most recently accessed first');
  });
}
