import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Account management for admins. Backed by the admin_create_user and
/// admin_update_user database functions, which check the caller is an admin.
class AdminService {
  /// Creates a student / faculty / admin account. The role and department
  /// come from the ID number. Returns an error message, or null on success.
  static Future<String?> createUser({
    required String idNumber,
    required String fullName,
    required String password,
    String? email,
  }) async {
    try {
      final authId =
          await SupabaseService.client.rpc('admin_create_user', params: {
        'p_id_number': idNumber.trim().toUpperCase(),
        'p_full_name': fullName.trim(),
        'p_password': password.trim(),
      });
      // Saved as the contact on file (also used for password resets).
      if ((email ?? '').trim().isNotEmpty && authId is String) {
        await setContact(authId, email!);
      }
      return null;
    } on PostgrestException catch (e) {
      return friendlyError(e.message);
    } catch (e) {
      return 'Could not create the account: $e';
    }
  }

  /// Changes the name and, when [newPassword] is given, resets the password.
  /// Returns an error message, or null on success.
  static Future<String?> updateUser({
    required String authId,
    required String fullName,
    String? newPassword,
  }) async {
    try {
      await SupabaseService.client.rpc('admin_update_user', params: {
        'p_auth_id': authId,
        'p_full_name': fullName.trim(),
        'p_new_password': newPassword?.trim(),
      });
      return null;
    } on PostgrestException catch (e) {
      return friendlyError(e.message);
    } catch (e) {
      return 'Could not update the account: $e';
    }
  }

  /// Accounts sent per request during a bulk import.
  static const bulkBatchSize = 50;

  /// Creates accounts in batches. [onProgress] gets (done, total).
  /// Returns an error message per ID number (null = created).
  static Future<Map<String, String?>> createUsersBulk(
    List<({String idNumber, String fullName, String password})> accounts, {
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <String, String?>{};
    for (var i = 0; i < accounts.length; i += bulkBatchSize) {
      final batch =
          accounts.sublist(i, (i + bulkBatchSize).clamp(0, accounts.length));
      try {
        final response = await SupabaseService.client
            .rpc('admin_create_users_bulk', params: {
          'p_users': [
            for (final a in batch)
              {
                'id_number': a.idNumber,
                'full_name': a.fullName,
                'password': a.password,
              }
          ],
        });
        for (final r in (response as List).cast<Map<String, dynamic>>()) {
          results[r['id_number'] as String] = r['ok'] == true
              ? null
              : friendlyError(r['error'] as String? ?? 'Failed');
        }
      } on PostgrestException catch (e) {
        for (final a in batch) {
          results[a.idNumber] = friendlyError(e.message);
        }
      } catch (e) {
        for (final a in batch) {
          results[a.idNumber] = 'Network error. Try again.';
        }
      }
      onProgress?.call(
          (i + batch.length).clamp(0, accounts.length), accounts.length);
    }
    return results;
  }

  /// Saves emails as contacts on file for accounts that were just created
  /// in bulk ([emails] maps ID number to email).
  static Future<void> saveBulkEmails(Map<String, String> emails) async {
    if (emails.isEmpty) return;
    try {
      final rows = await SupabaseService.client
          .from(SupabaseService.usersTable)
          .select('id_number, auth_id')
          .inFilter('id_number', emails.keys.toList());
      for (final row in rows) {
        final authId = row['auth_id'] as String?;
        final email = emails[row['id_number']];
        if (authId != null && email != null) await setContact(authId, email);
      }
    } catch (_) {
      // Accounts are created; emails can still be added in Edit Account.
    }
  }

  /// Approves a password reset with [temporaryPassword]; the user must
  /// change it on their next login. Returns an error message, or null.
  static Future<String?> resolvePasswordRequest({
    required String requestId,
    required String temporaryPassword,
  }) =>
      _call('admin_resolve_password_request', {
        'p_request_id': requestId,
        'p_temp_password': temporaryPassword.trim(),
      });

  /// Contact on file (email or phone), or null if there is none.
  static Future<String?> getContact(String authId) async {
    try {
      final row = await SupabaseService.client
          .from('user_contacts')
          .select('contact')
          .eq('auth_id', authId)
          .maybeSingle();
      return row?['contact'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Sets (or clears, when blank) the contact on file.
  static Future<String?> setContact(String authId, String contact) =>
      _call('admin_set_contact', {
        'p_auth_id': authId,
        'p_contact': contact.trim(),
      });

  /// Frees an account that is signed in on a device (e.g. a lost phone).
  static Future<String?> releaseDevice(String idNumber) =>
      _call('admin_release_device', {'p_id_number': idNumber});

  static Future<String?> _call(
      String function, Map<String, dynamic> params) async {
    try {
      await SupabaseService.client.rpc(function, params: params);
      return null;
    } on PostgrestException catch (e) {
      return friendlyError(e.message);
    } catch (e) {
      return 'Network error. Try again.';
    }
  }

  /// Closes a request without resetting (e.g. not a real request).
  static Future<String?> dismissPasswordRequest(String requestId) async {
    try {
      await SupabaseService.client.rpc('admin_dismiss_password_request',
          params: {'p_request_id': requestId});
      return null;
    } on PostgrestException catch (e) {
      return friendlyError(e.message);
    } catch (e) {
      return 'Network error. Try again.';
    }
  }

  /// Live list of open "forgot password" requests, oldest first.
  /// Not filtered on the server: a handled request must disappear, and a
  /// live stream would otherwise keep it.
  static Stream<List<Map<String, dynamic>>> pendingPasswordRequests() =>
      SupabaseService.client
          .from('password_reset_requests')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(300)
          .map((rows) {
            final pending = rows
                .cast<Map<String, dynamic>>()
                .where((r) => r['status'] == 'pending')
                .toList()
              ..sort((a, b) => (a['created_at'] as String? ?? '')
                  .compareTo(b['created_at'] as String? ?? ''));
            return pending;
          });

  static String friendlyError(String message) {
    if (message.contains('ID already registered')) {
      return 'This ID number already has an account.';
    }
    if (message.contains('Invalid ID format')) {
      return 'Invalid ID number format.';
    }
    if (message.contains('Request already handled')) {
      return 'This request was already handled.';
    }
    if (message.contains('admin_create_users_bulk') ||
        message.contains('password_request') ||
        message.contains('password_reset_requests') ||
        message.contains('account_request') ||
        message.contains('admin_set_contact') ||
        message.contains('user_contacts')) {
      return 'This feature is not set up on the server yet.';
    }
    if (message.contains('Only admins')) {
      return 'Only admins can manage accounts.';
    }
    if (message.contains('admin_create_user') ||
        message.contains('admin_update_user')) {
      // The migration hasn't been run on this Supabase project yet.
      return 'Account management is not set up on the server yet.';
    }
    return message;
  }

  /// Easy-to-read temporary password, e.g. "Shelf-4827-km".
  /// Avoids characters that are easy to confuse (0/O, 1/l).
  static String generatePassword() {
    final random = Random.secure();
    const words = ['Shelf', 'Read', 'Book', 'Page', 'Study', 'Learn', 'Note'];
    const letters = 'abcdefghjkmnpqrstuvwxyz';
    final digits = List.generate(4, (_) => random.nextInt(8) + 2).join();
    final tail =
        List.generate(2, (_) => letters[random.nextInt(letters.length)]).join();
    return '${words[random.nextInt(words.length)]}-$digits-$tail';
  }
}
