import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/auth_service.dart';
import 'forgot_password_screen.dart';
import 'student/student_home_screen.dart';
import 'teachers/teacher_shell.dart';
import 'admin/admin_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    final idText = _idController.text.trim();
    final password = _passwordController.text.trim();

    if (idText.isEmpty || password.isEmpty) {
      _showMessage('Please enter your ID and Password.', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService.login(
      idNumber: idText,
      password: password,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] != true) {
      _showMessage(result['message'] ?? 'Login failed.', isError: true);
      return;
    }

    final session = result['session'] as UserSession;

    if (result['offline'] == true) {
      _showMessage('Logged in offline. Some features are limited.');
    }
    if (result['usedRecovery'] == true) {
      _showMessage('Signed in with your recovery password. You can set a new '
          'everyday password in Settings.');
    }

    Widget destination;
    switch (session.role) {
      case 'admin':
        destination = AdminDashboardScreen(session: session);
        break;
      case 'instructor':
        destination = TeacherShell(
          key: ValueKey(session.idNumber),
          session: session,
        );
        break;
      case 'student':
      default:
        destination = StudentHomeScreen(
          key: ValueKey(session.idNumber),
          session: session,
        );
    }

    // Still on the admin's temporary password: a reminder only; it can be
    // changed any time in Settings.
    if (result['mustChangePassword'] == true) {
      _showMessage('Tip: you can change your password any time in '
          'Settings.');
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  void _showMessage(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
      ),
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3A86FF), Color(0xFF00B4D8)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF3A86FF).withValues(alpha: 0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.auto_stories_rounded,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Edushelf',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in to your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 36),

                  // ID field
                  TextField(
                    controller: _idController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'ID Number',
                      hintText: 'e.g., IT-23-01003',
                      hintStyle: const TextStyle(color: Color(0xFF475569)),
                      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.badge_outlined,
                          color: Color(0xFF94A3B8)),
                      filled: true,
                      fillColor: const Color(0xFF1C2541),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.lock_outline,
                          color: Color(0xFF94A3B8)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: const Color(0xFF94A3B8),
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1C2541),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ForgotPasswordScreen(
                              initialIdNumber: _idController.text.trim()),
                        ),
                      ),
                      child: const Text('Forgot password?',
                          style: TextStyle(color: Color(0xFF38BDF8))),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sign In button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3A86FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // No sign-up: the admin creates every account.
                  const Text(
                    "Don't have an account? Please contact the school admin.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
