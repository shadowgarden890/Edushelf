import 'dart:typed_data';

Future<Uint8List?> readFileBytes(String path) async {
  // Web doesn't have file paths — bytes come from the picker directly
  return null;
}
