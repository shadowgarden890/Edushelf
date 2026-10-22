import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/auth_service.dart';

/// Profile details (managed by the admin) and password change.
class AccountSettingsScreen extends StatefulWidget {
  final UserSession session;

  const AccountSettingsScreen({super.key, required this.session});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String get _roleLabel => switch (widget.session.role) {
        'admin' => 'Administrator',
        'instructor' => 'Faculty',
        _ => 'Student',
      };

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _saving = true);
    final error = await AuthService.changePassword(
      session: widget.session,
      currentPassword: _current.text,
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

    _current.clear();
    _new.clear();
    _confirm.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password changed. Use it the next time you log in.'),
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Account Settings',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // PROFILE
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2541),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      backgroundColor: Color(0xFF0B132B),
                      child: Icon(Icons.person,
                          size: 38, color: Color(0xFF38BDF8)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      s.fullName.isEmpty ? 'No name on file' : s.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _infoRow(Icons.badge_outlined, 'ID Number', s.idNumber),
                    _infoRow(Icons.work_outline, 'Role', _roleLabel),
                    _infoRow(Icons.school_outlined, 'Department', s.department),
                    const SizedBox(height: 8),
                    const Text(
                      'Your name and ID come from school records. Contact '
                      'the admin if anything is wrong.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // CHANGE PASSWORD
              const Text('Change Password',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                'If the admin gave you a temporary password, change it '
                'to one only you know.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _passwordField(_current, 'Current password',
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter your current password'
                            : null),
                    const SizedBox(height: 12),
                    _passwordField(_new, 'New password',
                        validator: (v) => (v ?? '').trim().length < 6
                            ? 'At least 6 characters'
                            : null),
                    const SizedBox(height: 12),
                    _passwordField(_confirm, 'Confirm new password',
                        validator: (v) => (v ?? '').trim() != _new.text.trim()
                            ? 'Passwords do not match'
                            : null),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A86FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saving ? null : _changePassword,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lock_reset_rounded, size: 18),
                label: Text(_saving ? 'Saving...' : 'Change Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _passwordField(TextEditingController controller, String label,
      {required String? Function(String?) validator}) {
    return TextFormField(
      controller: controller,
      obscureText: _obscure,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF64748B)),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show passwords' : 'Hide passwords',
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
