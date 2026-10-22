import 'package:edushelf_reading_application/screen/student/download_queue_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatBytes picks a readable unit', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(831898), '812.4 KB');
    expect(formatBytes(5 * 1024 * 1024 + 200 * 1024), '5.2 MB');
  });

  test('formatTimeLeft reads naturally', () {
    expect(formatTimeLeft(const Duration(milliseconds: 300)),
        'less than a second left');
    expect(formatTimeLeft(const Duration(seconds: 42)), '42 s left');
    expect(formatTimeLeft(const Duration(minutes: 2, seconds: 5)),
        '2 min 05 s left');
  });
}
