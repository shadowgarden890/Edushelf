import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../services/credential_slips.dart';
import '../../widgets/credentials_dialog.dart';
import 'request_widgets.dart';

/// "Forgot password" requests, oldest first and updated live. Approving
/// sets a temporary password that the admin sends to the contact ON FILE
/// (never one typed into the request, so nobody can redirect it).
class PasswordRequestsScreen extends StatefulWidget {
  const PasswordRequestsScreen({super.key});

  @override
  State<PasswordRequestsScreen> createState() => _PasswordRequestsScreenState();
}

class _PasswordRequestsScreenState extends State<PasswordRequestsScreen> {
  final _stream = AdminService.pendingPasswordRequests();
  final Set<String> _busy = {};

  Future<void> _approve(Map<String, dynamic> r) async {
    final contact = r['contact'] as String? ?? '';
    final ok = await confirmRequestAction(
      context,
      title: 'Reset password?',
      message: 'A temporary password will be set for ${r['full_name']} '
          '(${r['id_number']}). Their old password stops working, and they '
          'must choose a new one when they log in.'
          '${contact.isEmpty ? '\n\nThere is no contact on file: give it '
              'to them in person, or add a contact in Edit Account first.' : ''}',
      confirmLabel: 'Reset',
    );
    if (!ok) return;

    final password = AdminService.generatePassword();
    final success = await _run(
        r,
        () => AdminService.resolvePasswordRequest(
            requestId: r['id'], temporaryPassword: password));
    if (!success || !mounted) return;

    await showCredentialsDialog(
      context,
      AccountCredentials(
        fullName: r['full_name'] as String? ?? '',
        idNumber: r['id_number'] as String? ?? '',
        password: password,
      ),
      title: 'Password reset',
      sendTo: contact,
    );
  }

  Future<void> _dismiss(Map<String, dynamic> r) =>
      _run(r, () => AdminService.dismissPasswordRequest(r['id']),
          done: 'Request dismissed.');

  Future<bool> _run(Map<String, dynamic> r, Future<String?> Function() action,
      {String? done}) async {
    final id = r['id'] as String;
    setState(() => _busy.add(id));
    final error = await action();
    if (!mounted) return false;
    setState(() => _busy.remove(id));
    final msg = error ?? done;
    if (msg != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
    return error == null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: requestCardColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Password Requests',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: RequestQueue(
        stream: _stream,
        emptyText: 'No pending requests.\nUsers who forget their password '
            'can request a reset from the login screen.',
        errorText: (e) => AdminService.friendlyError(e.toString()),
        itemBuilder: (r, sameId) => RequestCard(
          request: r,
          icon: Icons.lock_reset_rounded,
          subtitle: r['id_number'] as String? ?? '',
          busy: _busy.contains(r['id']),
          sameIdCount: sameId,
          extraLines: [
            (
              Icons.alternate_email_rounded,
              (r['contact'] as String? ?? '').isEmpty
                  ? 'No contact on file - give the password in person'
                  : 'Send to: ${r['contact']} (on file)'
            ),
          ],
          primaryLabel: 'Reset password',
          primaryIcon: Icons.key_rounded,
          onPrimary: () => _approve(r),
          secondaryLabel: 'Dismiss',
          onSecondary: () => _dismiss(r),
        ),
      ),
    );
  }
}
