import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/auth_service.dart';

/// Shown after logging in with a temporary password. The user can't
/// continue until they set their own.
class ForcePasswordChangeScreen extends StatefulWidget {
  final UserSession session;
  final String temporaryPassword;
  final VoidCallback onChanged;

  const ForcePasswordChangeScreen({
    super.key,
    required this.session,
    required this.temporaryPassword,
    required this.onChanged,
  });

  @override
  State<ForcePasswordChangeScreen> createState() =>
      _ForcePasswordChangeScreenState();
}

class _ForcePasswordChangeScreenState extends State<ForcePasswordChangeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    final error = await AuthService.changePassword(
      session: widget.session,
      currentPassword: widget.temporaryPassword,
      newPassword: _new.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
      return;
    }
    widget.onChanged();
  }

  Future<void> _logOut() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  const Icon(Icons.password_rounded,
                      size: 56, color: Color(0xFF38BDF8)),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome, ${widget.session.fullName.isEmpty ? widget.session.idNumber : widget.session.fullName}!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You logged in with a temporary password. Set your own '
                    'password to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _field(_new, 'New password', validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.length < 6) return 'At least 6 characters';
                          if (t == widget.temporaryPassword.trim()) {
                            return 'Choose a different password';
                          }
                          return null;
                        }),
                        const SizedBox(height: 12),
                        _field(_confirm, 'Confirm new password',
                            validator: (v) =>
                                (v ?? '').trim() != _new.text.trim()
                                    ? 'Passwords do not match'
                                    : null),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3A86FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Set password and continue',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _logOut,
                    child: const Text('Log out',
                        style: TextStyle(color: Color(0xFF94A3B8))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {required String? Function(String?) validator}) {
    return TextFormField(
      controller: c,
      obscureText: _obscure,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF64748B)),
        suffixIcon: IconButton(
          icon: Icon(
              _obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: const Color(0xFF64748B)),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        filled: true,
        fillColor: const Color(0xFF1C2541),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
