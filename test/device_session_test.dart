import 'package:edushelf_reading_application/services/device_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a device keeps the same ID across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final id = await DeviceSession.instance.deviceId();
    expect(id, hasLength(32));
    expect(await DeviceSession.instance.deviceId(), id);
  });

  test('the blocked message says where the account is in use', () {
    final msg = DeviceSession.blockedMessage('a Windows computer');
    expect(msg, contains('already signed in on a Windows computer'));
    expect(msg, contains('ask the administrator'));
    expect(DeviceSession.blockedMessage(null), contains('another device'));
  });
}
