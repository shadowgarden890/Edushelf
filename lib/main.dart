import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screen/login_screen.dart';
import 'services/auth_service.dart';
import 'services/device_session.dart';
import 'web_pdf_registry.dart'
    if (dart.library.io) 'web_pdf_registry_stub.dart';

const String supabaseUrl = 'https://ypseyqamygvmhvboieom.supabase.co';
const String supabasePublishableKey =
    'sb_publishable_PzfTxGdhNkgQwboNsNCSoQ_AFdXF6Sj';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  registerWebPdfViewer();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  DeviceSession.instance.onSignedOutElsewhere = _signedOutElsewhere;

  runApp(const EduShelfApp());
}

final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

/// This device lost its claim on the account (signed in elsewhere, or
/// signed out by the admin): back to the login screen.
Future<void> _signedOutElsewhere() async {
  await AuthService.logout();
  _navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false);
  _messengerKey.currentState?.showSnackBar(const SnackBar(
    duration: Duration(seconds: 8),
    content: Text('You were signed out because this account is now being '
        'used on another device, or the administrator signed it out.'),
  ));
}

class EduShelfApp extends StatelessWidget {
  const EduShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Edushelf',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: const Color(0xFF0B132B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A86FF),
          brightness: Brightness.dark,
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
