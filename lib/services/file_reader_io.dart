import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readFileBytes(String path) async {
  try {
    final file = File(path);
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
