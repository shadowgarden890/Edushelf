import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import '../../services/account_import.dart' show isValidEmail;
import '../../services/admin_service.dart';
import '../../services/credential_slips.dart';
import '../../widgets/credentials_dialog.dart';
import '../../widgets/request_form.dart' show isValidContact;

const _card = Color(0xFF1C2541);
const _field = Color(0xFF0B132B);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFFFBBF24);

/// Create-account form. Shows the login details to hand over on success.
Future<void> showCreateUserDialog(BuildContext context) async {
  final created = await showDialog<AccountCredentials>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CreateUserDialog(),
  );
  if (created != null && context.mounted) {
    await showCredentialsDialog(context, created,
        title: 'Account created', sendTo: created.email);
  }
}

/// Edit-account form for an existing `users` row.
Future<void> showEditUserDialog(
    BuildContext context, Map<String, dynamic> user) async {
  final reset = await showDialog<(AccountCredentials, String)>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EditUserDialog(user: user),
  );
  if (reset != null && context.mounted) {
    await showCredentialsDialog(context, reset.$1,
        title: 'Password reset', sendTo: reset.$2);
  }
}

// =====================================================================
// CREATE
// =====================================================================
class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password =
      TextEditingController(text: AdminService.generatePassword());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final error = await AdminService.createUser(
      idNumber: _id.text,
      fullName: _name.text,
      password: _password.text,
      email: _email.text,
    );
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.pop(
      context,
      AccountCredentials(
          fullName: _name.text.trim(),
          idNumber: _id.text.trim().toUpperCase(),
          password: _password.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = UserSession.parseId(_id.text);

    return _FormDialog(
      title: 'Create Account',
      icon: Icons.person_add_alt_1_rounded,
      error: _error,
      saving: _saving,
      submitLabel: 'Create',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField(
              controller: _id,
              label: 'ID Number',
              hint: 'IT-23-01003, IT-T-00001, ADMIN-0002',
              icon: Icons.badge_outlined,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              validator: (v) => UserSession.parseId(v ?? '') == null
                  ? 'Use a valid ID format'
                  : null,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                parsed == null
                    ? 'Students: DD-YY-NNNNN • Faculty: DD-T-NNNNN • '
                        'Admin: ADMIN-NNNN (DD = IT, BA, AC, OA)'
                    : 'Will be created as: ${_roleName(parsed['role']!)} • '
                        '${parsed['department']}',
                style: TextStyle(
                    color: parsed == null ? _muted : const Color(0xFF10B981),
                    fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 14),
            _textField(
              controller: _name,
              label: 'Full Name',
              hint: 'As written in school records',
              icon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the full name' : null,
            ),
            const SizedBox(height: 14),
            _textField(
              controller: _email,
              label: 'Email (optional)',
              hint: 'To send the login details',
              icon: Icons.email_outlined,
              validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || isValidEmail(t)
                    ? null
                    : 'Enter a valid email address';
              },
            ),
            const SizedBox(height: 14),
            _passwordField(
                _password,
                parsed?['role'] == 'admin'
                    ? 'Recovery Password'
                    : 'Temporary Password',
                onGenerate: () => setState(
                    () => _password.text = AdminService.generatePassword())),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                parsed?['role'] == 'admin'
                    ? "This first password is the admin's permanent recovery "
                        'password (master key). It always works for logging '
                        'in, even after they change their everyday password. '
                        'Keep it somewhere safe.'
                    : 'Give this to the user. They must set their own '
                        'password the first time they log in.',
                style: TextStyle(
                    color: parsed?['role'] == 'admin'
                        ? const Color(0xFFFBBF24)
                        : _muted,
                    fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// EDIT
// =====================================================================
class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.user});

  final Map<String, dynamic> user;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.user['full_name'] as String? ?? '');
  final _password = TextEditingController();
  final _contact = TextEditingController();
  String _savedContact = '';
  bool _loadingContact = true;
  bool _resetPassword = false;
  bool _saving = false;
  String? _error;

  String get _idNumber => widget.user['id_number'] as String? ?? '';
  String? get _authId => widget.user['auth_id'] as String?;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    final id = _authId;
    final contact = id == null ? null : await AdminService.getContact(id);
    if (!mounted) return;
    setState(() {
      _savedContact = contact ?? '';
      _contact.text = _savedContact;
      _loadingContact = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final authId = widget.user['auth_id'] as String?;
    if (authId == null) {
      setState(() => _error = 'This account has no login yet. Run the '
          'Supabase Auth migration first.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await AdminService.updateUser(
      authId: authId,
      fullName: _name.text,
      newPassword: _resetPassword ? _password.text : null,
    );
    var failure = error;
    if (failure == null && _contact.text.trim() != _savedContact) {
      failure = await AdminService.setContact(authId, _contact.text);
    }
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _saving = false;
        _error = failure;
      });
      return;
    }

    if (_resetPassword) {
      Navigator.pop(context, (
        AccountCredentials(
            fullName: _name.text.trim(),
            idNumber: _idNumber,
            password: _password.text.trim()),
        _contact.text.trim(),
      ));
    } else {
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Account updated.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.user['role'] as String? ?? 'student';
    final dept = widget.user['department'] as String? ?? '';

    return _FormDialog(
      title: 'Edit Account',
      icon: Icons.manage_accounts_rounded,
      error: _error,
      saving: _saving,
      submitLabel: 'Save',
      onSubmit: _submit,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_idNumber,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text('${_roleName(role)} • $dept',
                style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 16),
            _textField(
              controller: _name,
              label: 'Full Name',
              icon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter the full name' : null,
            ),
            const SizedBox(height: 14),
            _textField(
              controller: _contact,
              label: _loadingContact ? 'Loading contact...' : 'Email or phone',
              hint: 'Where temporary passwords are sent',
              icon: Icons.alternate_email_rounded,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty || isValidContact(t)) return null;
                return 'Enter a valid email or phone number';
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: _accent,
              title: const Text('Reset password',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('For users who forgot their password',
                  style: TextStyle(color: _muted, fontSize: 11.5)),
              value: _resetPassword,
              onChanged: (on) => setState(() {
                _resetPassword = on;
                if (on && _password.text.isEmpty) {
                  _password.text = AdminService.generatePassword();
                }
              }),
            ),
            if (_resetPassword)
              _passwordField(_password, 'New Temporary Password',
                  onGenerate: () => setState(
                      () => _password.text = AdminService.generatePassword())),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// SHARED PIECES
// =====================================================================
String _roleName(String role) => switch (role) {
      'admin' => 'Administrator',
      'instructor' => 'Faculty',
      _ => 'Student',
    };

class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.icon,
    required this.child,
    required this.saving,
    required this.submitLabel,
    required this.onSubmit,
    this.error,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final bool saving;
  final String submitLabel;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(icon, color: _accent),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!,
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: _muted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _accent, foregroundColor: Colors.black),
          onPressed: saving ? null : onSubmit,
          child: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black),
                )
              : Text(submitLabel),
        ),
      ],
    );
  }
}

Widget _textField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  String? hint,
  TextCapitalization textCapitalization = TextCapitalization.none,
  ValueChanged<String>? onChanged,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    textCapitalization: textCapitalization,
    onChanged: onChanged,
    validator: validator,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
      filled: true,
      fillColor: _field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

Widget _passwordField(TextEditingController controller, String label,
    {required VoidCallback onGenerate}) {
  return TextFormField(
    controller: controller,
    style: const TextStyle(color: Colors.white, letterSpacing: 0.5),
    validator: (v) =>
        (v ?? '').trim().length < 6 ? 'At least 6 characters' : null,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _muted),
      prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFF64748B)),
      suffixIcon: IconButton(
        tooltip: 'Generate a new password',
        icon: const Icon(Icons.refresh_rounded, color: _accent),
        onPressed: onGenerate,
      ),
      filled: true,
      fillColor: _field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
