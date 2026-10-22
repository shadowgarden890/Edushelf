import 'package:flutter/material.dart';
import '../models/user_session.dart';
import '../services/auth_service.dart';
import '../widgets/request_form.dart';

/// Lets a user who forgot their password ask the admin for a new one.
/// The admin sends a temporary password to the contact on file.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialIdNumber;

  const ForgotPasswordScreen({super.key, this.initialIdNumber = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with RequestCooldown {
  final _formKey = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.initialIdNumber);
  final _name = TextEditingController();
  final _note = TextEditingController();

  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // Admins have a permanent recovery password (their first password),
    // so there's nobody to ask - they just log in with it.
    if (UserSession.parseId(_id.text)?['role'] == 'admin') {
      await _showAdminRecoveryInfo();
      return;
    }

    setState(() => _sending = true);

    final result = await AuthService.requestPasswordReset(
      idNumber: _id.text,
      fullName: _name.text,
      note: _note.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result == 'submitted') {
      setState(() => _sent = true);
      startCooldown(AuthService.requestCooldown);
      return;
    }
    if (result == 'cooldown') {
      startCooldown(
          await AuthService.requestCooldownRemaining('reset', _id.text));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(requestResultMessage(result)!)));
  }

  Future<void> _showAdminRecoveryInfo() {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.key_rounded, color: Color(0xFFFBBF24)),
            SizedBox(width: 10),
            Expanded(
              child: Text('Use your recovery password',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: const Text(
          "Admin accounts don't need to request a reset. Go back and log in "
          'with your ID number and your recovery password (the first '
          'password of your admin account). It always works, even if you '
          'changed your password later.',
          style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3A86FF),
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Back to login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Forgot Password',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.lock_reset_rounded,
                  size: 56, color: Color(0xFF38BDF8)),
              const SizedBox(height: 16),
              const Text(
                'Request a new password',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your ID number and full name as they appear in school '
                'records. The admin will send a temporary password to the '
                'email or phone number on your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), height: 1.4),
              ),
              const SizedBox(height: 24),
              if (_sent)
                requestSentCard(
                  context,
                  title: 'Request sent',
                  // Same message whether or not the ID exists, so this
                  // screen can't be used to find valid IDs.
                  message: 'If the ID number and name match school records, '
                      'the admin will send a temporary password to the '
                      'contact on your account. Log in with it, then set '
                      'your own password.',
                )
              else
                _buildForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          requestField(_id, 'ID Number', Icons.badge_outlined,
              caps: TextCapitalization.characters,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter your ID number' : null),
          const SizedBox(height: 14),
          requestField(_name, 'Full Name', Icons.person_outline,
              caps: TextCapitalization.words,
              helper: 'As written in school records',
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter your full name' : null),
          const SizedBox(height: 14),
          requestField(
              _note, 'Message to admin (optional)', Icons.notes_rounded,
              maxLength: 300, maxLines: 3),
          const SizedBox(height: 10),
          requestSubmitButton(
            sending: _sending,
            coolingDown: isCoolingDown,
            cooldownLabel: cooldownLabel,
            label: 'Send request',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
