import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_session.dart';
import 'supabase_service.dart';

class AuthService {
  // Supabase Auth needs an email, so each ID number maps to an internal
  // address. Must match the domain in supabase/migrations.
  static const String authEmailDomain = 'edushelf.app';

  static const int _hashIterations = 10000;

  static const String _kOfflineId = 'offline_id';
  static const String _kOfflineName = 'offline_name';
  static const String _kOfflineRole = 'offline_role';
  static const String _kOfflineDepartment = 'offline_department';
  static const String _kOfflineSalt = 'offline_salt';
  static const String _kOfflineHash = 'offline_hash';
  // Written by older versions of the app (plaintext). Always removed.
  static const String _kLegacyOfflinePassword = 'offline_password';

  static String emailForId(String idNumber) =>
      '${idNumber.trim().toLowerCase()}@$authEmailDomain';

  // ================================================
  // CHANGE PASSWORD (signed-in user)
  // ================================================
  /// Returns an error message, or null on success.
  static Future<String?> changePassword({
    required UserSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    final current = currentPassword.trim();
    final next = newPassword.trim();
    if (next.length < 6) {
      return 'New password must be at least 6 characters.';
    }
    if (next == current) {
      return 'New password must be different from the current one.';
    }

    final auth = SupabaseService.client.auth;
    try {
      // Confirm the current password before changing it.
      await auth.signInWithPassword(
        email: emailForId(session.idNumber),
        password: current,
      );
    } on AuthRetryableFetchException {
      return 'No internet connection. Please try again.';
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials') {
        return 'Current password is incorrect.';
      }
      return e.message;
    } catch (_) {
      return 'No internet connection. Please try again.';
    }

    try {
      await auth.updateUser(UserAttributes(password: next));
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not change the password: $e';
    }

    try {
      // Clears the "change your temporary password" requirement.
      await SupabaseService.client.rpc('complete_password_change');
    } catch (_) {
      // The password itself is changed; the flag is cleared next time.
    }

    // Keep offline login working with the new password.
    await _saveOfflineCredentials(session: session, password: next);
    return null;
  }

  // ================================================
  // REQUESTS TO THE ADMIN (not signed in)
  // ================================================
  /// Wait between requests of the same kind from this phone for one ID.
  static const requestCooldown = Duration(minutes: 2);

  /// Asks the admin for a new password; they send a temporary one to the
  /// contact on file. Returns 'submitted', 'cooldown', 'rate_limited',
  /// 'offline' or 'error'.
  static Future<String> requestPasswordReset({
    required String idNumber,
    required String fullName,
    String? note,
  }) =>
      _sendRequest('reset', idNumber, 'request_password_reset', {
        'p_id_number': idNumber.trim().toUpperCase(),
        'p_full_name': fullName.trim(),
        'p_note': _blankToNull(note),
      });

  static String? _blankToNull(String? v) =>
      (v ?? '').trim().isEmpty ? null : v!.trim();

  static const _knownResults = {
    'submitted',
    'invalid_id',
    'invalid_contact',
    'invalid',
    'rate_limited',
  };

  static Future<String> _sendRequest(String kind, String idNumber,
      String function, Map<String, dynamic> params) async {
    final id = idNumber.trim().toUpperCase();
    if (await requestCooldownRemaining(kind, id) > Duration.zero) {
      return 'cooldown';
    }

    try {
      final result = await SupabaseService.client
          .rpc(function, params: params)
          .timeout(const Duration(seconds: 15));

      if (result == 'submitted') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            '${kind}_request_$id', DateTime.now().millisecondsSinceEpoch);
      }
      return _knownResults.contains(result) ? result as String : 'error';
    } on PostgrestException {
      return 'error';
    } on TimeoutException {
      return 'offline';
    } catch (_) {
      return 'offline';
    }
  }

  static Future<Duration> requestCooldownRemaining(
      String kind, String idNumber) async {
    final prefs = await SharedPreferences.getInstance();
    final last =
        prefs.getInt('${kind}_request_${idNumber.trim().toUpperCase()}');
    if (last == null) return Duration.zero;
    final elapsed =
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last));
    final remaining = requestCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ================================================
  // LOGIN
  // ================================================
  static Future<Map<String, dynamic>> login({
    required String idNumber,
    required String password,
    bool triedRecovery = false,
  }) async {
    final id = idNumber.trim().toUpperCase();
    final pass = password.trim();

    try {
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: emailForId(id),
        password: pass,
      );

      final profile = await SupabaseService.client
          .from(SupabaseService.usersTable)
          .select()
          .eq('auth_id', response.user!.id)
          .maybeSingle();

      if (profile == null) {
        await SupabaseService.client.auth.signOut();
        return {'success': false, 'message': 'Account profile not found.'};
      }

      final session = UserSession.fromMap(profile);
      final mustChange = profile['must_change_password'] == true;

      // A temporary password must not unlock offline login; the cache is
      // saved once the user has set their own password.
      if (!mustChange) {
        await _saveOfflineCredentials(session: session, password: pass);
      }

      return {
        'success': true,
        'session': session,
        'mustChangePassword': mustChange,
      };
    } on AuthRetryableFetchException catch (e) {
      return _offlineOrError(id: id, password: pass, error: e);
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials') {
        // Admins can always get in with their recovery (first) password,
        // like a master key.
        if (!triedRecovery &&
            UserSession.parseId(id)?['role'] == 'admin' &&
            await _adminRecover(id, pass)) {
          final result =
              await login(idNumber: id, password: pass, triedRecovery: true);
          if (result['success'] == true) result['usedRecovery'] = true;
          return result;
        }
        return {'success': false, 'message': 'Invalid ID or password.'};
      }
      return {'success': false, 'message': e.message};
    } catch (e) {
      // Network unreachable — try offline cache
      return _offlineOrError(id: id, password: pass, error: e);
    }
  }

  /// True when [password] is the admin's recovery password; the server
  /// then makes it the current password again.
  static Future<bool> _adminRecover(String id, String password) async {
    try {
      final ok =
          await SupabaseService.client.rpc('admin_recover_login', params: {
        'p_id_number': id,
        'p_password': password,
      }).timeout(const Duration(seconds: 15));
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> _offlineOrError({
    required String id,
    required String password,
    required Object error,
  }) async {
    final offline = await _tryOfflineLogin(id: id, password: password);
    if (offline['success'] == true) return offline;

    return {
      'success': false,
      'message': 'Connection failed: ${error.toString()}',
    };
  }

  // ================================================
  // OFFLINE FALLBACK
  // ================================================
  static Future<Map<String, dynamic>> _tryOfflineLogin({
    required String id,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final cachedId = prefs.getString(_kOfflineId);
    final cachedSalt = prefs.getString(_kOfflineSalt);
    final cachedHash = prefs.getString(_kOfflineHash);

    if (cachedId == null || cachedSalt == null || cachedHash == null) {
      return {
        'success': false,
        'message': 'No internet and no saved session.',
      };
    }

    if (cachedId.toUpperCase() == id &&
        hashPassword(password, cachedSalt) == cachedHash) {
      return {
        'success': true,
        'offline': true,
        'session': UserSession(
          idNumber: cachedId,
          fullName: prefs.getString(_kOfflineName) ?? '',
          role: prefs.getString(_kOfflineRole) ?? 'student',
          department: prefs.getString(_kOfflineDepartment) ?? 'BSIT',
        ),
      };
    }

    return {'success': false, 'message': 'Invalid ID or password.'};
  }

  // ================================================
  // SAVE OFFLINE CREDENTIALS
  // ================================================
  static Future<void> _saveOfflineCredentials({
    required UserSession session,
    required String password,
  }) async {
    final salt = _generateSalt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kOfflineId, session.idNumber);
    await prefs.setString(_kOfflineName, session.fullName);
    await prefs.setString(_kOfflineRole, session.role);
    await prefs.setString(_kOfflineDepartment, session.department);
    await prefs.setString(_kOfflineSalt, salt);
    await prefs.setString(_kOfflineHash, hashPassword(password, salt));
    await prefs.remove(_kLegacyOfflinePassword);
  }

  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// PBKDF2-HMAC-SHA256 (single 32-byte block), base64-encoded.
  /// Used only to verify the password for offline login.
  static String hashPassword(String password, String salt) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final block = Uint8List.fromList([...base64Decode(salt), 0, 0, 0, 1]);

    var u = hmac.convert(block).bytes;
    final result = Uint8List.fromList(u);
    for (var i = 1; i < _hashIterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return base64Encode(result);
  }

  // ================================================
  // LOGOUT
  // ================================================
  static Future<void> logout() async {
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {
      // Offline: the local session is still cleared by signOut.
    }

    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _kOfflineId,
      _kOfflineName,
      _kOfflineRole,
      _kOfflineDepartment,
      _kOfflineSalt,
      _kOfflineHash,
      _kLegacyOfflinePassword,
      'session_active',
    ]) {
      await prefs.remove(key);
    }
  }
}
