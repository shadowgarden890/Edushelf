import 'package:connectivity_plus/connectivity_plus.dart';
import 'supabase_service.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();

  /// Check if we're online.
  /// 1. Checks the device network adapter.
  /// 2. Pings Supabase with a quick query.
  ///
  /// This works on Edge DevTools "Offline" mode too.
  static Future<bool> isOnline() async {
    // 1. Device-level check
    final results = await _connectivity.checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      return false;
    }

    // 2. Ping Supabase
    try {
      await SupabaseService.client
          .from(SupabaseService.usersTable)
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stream that polls connectivity every 5 seconds.
  static Stream<bool> onStatusChanged() async* {
    while (true) {
      yield await isOnline();
      await Future.delayed(const Duration(seconds: 5));
    }
  }
}
