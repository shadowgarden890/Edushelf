import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// Keeps each account signed in on one device at a time.
///
/// Signing in claims the account for this device; another device is
/// refused while this one is in use. While the app is open it checks in
/// every [heartbeat]; after 10 minutes without a check-in the server
/// frees the account. If this device loses the claim (the admin freed
/// it, or another device took over after this one went quiet), it is
/// signed out through [onSignedOutElsewhere].
class DeviceSession with WidgetsBindingObserver {
  DeviceSession._();
  static final DeviceSession instance = DeviceSession._();

  static const heartbeat = Duration(minutes: 2);
  static const _kDeviceId = 'device_id';

  Timer? _timer;
  String? _deviceId;
  bool _active = false;

  /// Called when this device was signed out because the account is now
  /// used elsewhere. Set once by the app.
  VoidCallback? onSignedOutElsewhere;

  /// A random ID for this installation, kept across restarts.
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kDeviceId);
    if (id == null) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString(_kDeviceId, id);
    }
    return _deviceId = id;
  }

  static String get deviceName {
    if (kIsWeb) return 'a web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'an Android phone',
      TargetPlatform.iOS => 'an iPhone',
      TargetPlatform.windows => 'a Windows computer',
      TargetPlatform.macOS => 'a Mac',
      TargetPlatform.linux => 'a Linux computer',
      _ => 'another device',
    };
  }

  /// Claims the signed-in account for this device. Returns null when
  /// allowed, or a message saying where the account is in use.
  Future<String?> claim() async {
    try {
      final result = await SupabaseService.client.rpc('claim_device', params: {
        'p_device_id': await deviceId(),
        'p_device_name': deviceName,
      });
      final map = (result as Map).cast<String, dynamic>();
      if (map['ok'] == true) {
        _start();
        return null;
      }
      if (map['reason'] == 'no_profile') return null;
      return blockedMessage(map['device'] as String?);
    } catch (_) {
      // Not set up on the server yet, or a network hiccup: don't lock
      // anyone out.
      return null;
    }
  }

  static String blockedMessage(String? device) =>
      'This account is already signed in on ${device ?? 'another device'}. '
      'Log out there first. If that device is lost or closed, try again '
      'in 10 minutes or ask the administrator to sign it out.';

  /// Frees the account (on logout).
  Future<void> release() async {
    _stop();
    try {
      await SupabaseService.client.rpc('release_device', params: {
        'p_device_id': await deviceId()
      }).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline: the server frees it after 10 minutes.
    }
  }

  void _start() {
    _stop();
    _active = true;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(heartbeat, (_) => _checkIn());
  }

  void _stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  // Phones pause timers in the background; check in on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _active) _checkIn();
  }

  Future<void> _checkIn() async {
    bool stillMine;
    try {
      final r = await SupabaseService.client
          .rpc('device_heartbeat', params: {'p_device_id': await deviceId()});
      stillMine = r == true;
    } catch (_) {
      return; // Offline or a hiccup: try again next time.
    }
    if (stillMine || !_active) return;

    _stop();
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {}
    onSignedOutElsewhere?.call();
  }
}
