import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/credential_slips.dart';

const _card = Color(0xFF1C2541);
const _field = Color(0xFF0B132B);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFFFBBF24);

/// Share the login details through the phone's share menu
/// (Messenger, Gmail, SMS...).
Future<void> shareCredentials(AccountCredentials c) =>
    SharePlus.instance.share(ShareParams(
      text: c.shareText,
      subject: 'Your Edushelf account',
    ));

/// Opens an email (or SMS) addressed to [contact] with the login details
/// filled in. On phones this opens the Gmail / mail app; on a laptop it
/// opens Gmail in the browser, whatever the default mail app is.
/// Falls back to the share menu if that fails.
Future<void> sendCredentialsTo(String contact, AccountCredentials c) async {
  final to = contact.trim();
  final subject = Uri.encodeComponent('Your Edushelf account');
  final body = Uri.encodeComponent(c.shareText);
  final isDesktop = kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  final Uri uri;
  if (!to.contains('@')) {
    uri = Uri.parse('sms:${to.replaceAll(RegExp(r'[^\d+]'), '')}?body=$body');
  } else if (isDesktop) {
    // Gmail's compose window, already filled in.
    uri = Uri.parse('https://mail.google.com/mail/?view=cm&fs=1'
        '&to=${Uri.encodeComponent(to)}&su=$subject&body=$body');
  } else {
    uri = Uri.parse(
        'mailto:${Uri.encodeComponent(to)}?subject=$subject&body=$body');
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened) await shareCredentials(c);
}

/// Opens the print / save-as-PDF screen with login slips.
Future<void> printCredentialSlips(List<AccountCredentials> list) =>
    Printing.layoutPdf(
      name: 'Edushelf login slips',
      onLayout: (_) => buildCredentialSlipsPdf(list),
    );

/// Shares the list as a CSV file for the admin's records.
Future<void> shareCredentialsCsv(List<AccountCredentials> list) =>
    SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(credentialsToCsv(list)),
          mimeType: 'text/csv',
          name: 'edushelf_accounts.csv',
        ),
      ],
      fileNameOverrides: ['edushelf_accounts.csv'],
      subject: 'Edushelf accounts',
    ));

/// Shows one account's login details with Copy / Share / Print, plus
/// "Send to ..." when the user's email or phone is known.
Future<void> showCredentialsDialog(
  BuildContext context,
  AccountCredentials c, {
  required String title,
  String? sendTo,
}) {
  final contact = (sendTo ?? '').trim();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              contact.isEmpty
                  ? 'Give these login details to the user:'
                  : 'Send these login details to $contact:',
              style: const TextStyle(color: _muted, fontSize: 13)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _field,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              'Name: ${c.fullName}\nID Number: ${c.idNumber}\n'
              'Password: ${c.password}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.6),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This password is shown only now. The user must set their own '
            'password when they first log in.',
            style: TextStyle(color: _muted, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          if (contact.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => sendCredentialsTo(contact, c),
                icon: Icon(
                    contact.contains('@')
                        ? Icons.email_outlined
                        : Icons.sms_outlined,
                    size: 18),
                label:
                    Text('Send to $contact', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action(Icons.copy_rounded, 'Copy', () async {
                await Clipboard.setData(ClipboardData(text: c.shareText));
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Login details copied.')));
              }),
              _action(Icons.share_rounded, 'Share', () => shareCredentials(c)),
              _action(Icons.print_rounded, 'Print slip',
                  () => printCredentialSlips([c])),
            ],
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _accent, foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Widget _action(IconData icon, String label, VoidCallback onTap) {
  return OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: _accent,
      side: const BorderSide(color: Color(0xFF334155)),
    ),
    onPressed: onTap,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}
