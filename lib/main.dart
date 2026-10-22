import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screen/login_screen.dart';
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

  runApp(const EduShelfApp());
}

class EduShelfApp extends StatelessWidget {
  const EduShelfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
