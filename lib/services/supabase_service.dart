import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  // CENTRAL CLIENT —

  static SupabaseClient get client => Supabase.instance.client;

  // TABLES

  static const String usersTable = 'users';
  static const String materialsTable = 'materials';
  static const String notificationsTable = 'notifications';
  static const String permissionsTable = 'permissions';
  static const String activityLogsTable = 'activity_logs';

  // STORAGE BUCKET

  static const String materialsBucket = 'materials';

  // STORAGE HELPERS

  /// Upload a file to Supabase Storage and return its public URL.
  static Future<String> uploadFile({
    required List<int> fileBytes,
    required String fileName,
    required String folder,
  }) async {
    final path = '$folder/$fileName';

    await client.storage.from(materialsBucket).uploadBinary(
          path,
          Uint8List.fromList(fileBytes),
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'application/pdf',
          ),
        );

    return client.storage.from(materialsBucket).getPublicUrl(path);
  }

  /// Delete a file from storage.
  static Future<void> deleteFile(String fileUrl) async {
    try {
      final uri = Uri.parse(fileUrl);
      final pathSegments = uri.pathSegments;
      final bucketIndex = pathSegments.indexOf(materialsBucket);
      if (bucketIndex == -1) return;
      final filePath = pathSegments.sublist(bucketIndex + 1).join('/');
      await client.storage.from(materialsBucket).remove([filePath]);
    } catch (_) {
      // Silently ignore delete failures
    }
  }
}
