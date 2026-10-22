import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/account_import.dart';
import '../../services/admin_service.dart';
import '../../services/credential_slips.dart';
import '../../widgets/credentials_dialog.dart';

const _card = Color(0xFF1C2541);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFFFBBF24);
const _green = Color(0xFF10B981);
const _red = Color(0xFFEF4444);

/// Creates many accounts from a CSV of school records.
class BulkImportScreen extends StatefulWidget {
  const BulkImportScreen({super.key});

  @override
  State<BulkImportScreen> createState() => _BulkImportScreenState();
}

class _BulkImportScreenState extends State<BulkImportScreen> {
  String? _fileName;
  List<ImportRow> _rows = [];

  bool _creating = false;
  int _done = 0;

  /// After creating: accounts made, and failures by ID number.
  List<AccountCredentials>? _created;
  Map<String, String> _failed = {};

  List<ImportRow> get _valid => _rows.where((r) => r.isValid).toList();
  List<ImportRow> get _invalid => _rows.where((r) => !r.isValid).toList();

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null || file.bytes == null) return;

    final rows =
        readAccountsCsv(utf8.decode(file.bytes!, allowMalformed: true));
    setState(() {
      _fileName = file.name;
      _rows = rows;
      _created = null;
      _failed = {};
    });
    if (rows.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No rows found in that file.')));
    }
  }

  Future<void> _shareTemplate() => SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(utf8.encode(accountsCsvTemplate),
              mimeType: 'text/csv', name: 'edushelf_accounts_template.csv'),
        ],
        fileNameOverrides: ['edushelf_accounts_template.csv'],
        subject: 'Edushelf accounts template',
      ));

  Future<void> _create() async {
    final valid = _valid;
    final accounts = [
      for (final r in valid)
        (
          idNumber: r.idNumber,
          fullName: r.fullName,
          password: AdminService.generatePassword(),
        )
    ];
    final emails = {
      for (final r in valid)
        if (r.email != null) r.idNumber: r.email!,
    };

    setState(() {
      _creating = true;
      _done = 0;
    });

    final results = await AdminService.createUsersBulk(
      accounts,
      onProgress: (done, _) {
        if (mounted) setState(() => _done = done);
      },
    );
    // Emails become each new account's contact on file.
    await AdminService.saveBulkEmails({
      for (final e in emails.entries)
        if (results.containsKey(e.key) && results[e.key] == null)
          e.key: e.value,
    });
    if (!mounted) return;

    setState(() {
      _creating = false;
      _created = [
        for (final a in accounts)
          if (results.containsKey(a.idNumber) && results[a.idNumber] == null)
            AccountCredentials(
                fullName: a.fullName,
                idNumber: a.idNumber,
                password: a.password,
                email: emails[a.idNumber]),
      ];
      _failed = {
        for (final e in results.entries)
          if (e.value != null) e.key: e.value!,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _card,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Import Accounts',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: _created != null ? _buildResults() : _buildSetup(),
          ),
        ),
      ),
    );
  }

  // ================================================
  // STEP 1-2: PICK FILE, REVIEW
  // ================================================
  Widget _buildSetup() {
    final valid = _valid;
    final invalid = _invalid;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create accounts from school records',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const SizedBox(height: 8),
              const Text(
                '1. Export the student / faculty list as CSV (in Excel: '
                'File → Save As → CSV).\n'
                '2. It needs an "ID Number" and a "Full Name" column, and '
                'can have an optional "Email" column.\n'
                '3. Each account gets its own temporary password. Users '
                'must change it the first time they log in.',
                style: TextStyle(color: _muted, fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.black),
                    onPressed: _creating ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: Text(_fileName == null
                        ? 'Choose CSV file'
                        : 'Choose another file'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: const BorderSide(color: Color(0xFF334155))),
                    onPressed: _shareTemplate,
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Get template'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_fileName != null) ...[
          const SizedBox(height: 20),
          Text(_fileName!,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${valid.length} ready • ${invalid.length} with problems',
            style: TextStyle(
                color: invalid.isEmpty ? _green : _accent, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (_creating) ...[
            LinearProgressIndicator(
              value: valid.isEmpty ? null : _done / valid.length,
              backgroundColor: const Color(0xFF0B132B),
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 6),
            Text('Creating accounts... $_done of ${valid.length}',
                style: const TextStyle(color: _muted, fontSize: 12)),
          ] else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: valid.isEmpty ? null : _create,
              icon: const Icon(Icons.group_add_rounded),
              label: Text('Create ${valid.length} '
                  'account${valid.length == 1 ? '' : 's'}'),
            ),
          if (invalid.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Will be skipped',
                style: TextStyle(color: _red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...invalid.map((r) => _rowTile(
                r.idNumber.isEmpty ? '(no ID)' : r.idNumber,
                r.fullName,
                'Line ${r.line}: ${r.error}',
                _red)),
          ],
          if (valid.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Ready to create',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...valid.map((r) => _rowTile(
                r.idNumber,
                r.fullName,
                '${_roleName(r.parsed!['role']!)} • ${r.parsed!['department']}',
                _muted)),
          ],
        ],
      ],
    );
  }

  // ================================================
  // STEP 3: RESULTS
  // ================================================
  Widget _buildResults() {
    final created = _created!;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: _green),
                  const SizedBox(width: 10),
                  Text(
                      '${created.length} account'
                      '${created.length == 1 ? '' : 's'} created',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              if (_failed.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('${_failed.length} could not be created (see below)',
                    style: const TextStyle(color: _red, fontSize: 12.5)),
              ],
              const SizedBox(height: 10),
              const Text(
                'Hand out the login details now. The temporary passwords '
                'are not stored and cannot be shown again.',
                style: TextStyle(color: _muted, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              if (created.isNotEmpty)
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.black),
                      onPressed: () => printCredentialSlips(created),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print login slips'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _accent,
                          side: const BorderSide(color: Color(0xFF334155))),
                      onPressed: () => shareCredentialsCsv(created),
                      icon: const Icon(Icons.table_chart_outlined, size: 18),
                      label: const Text('Export CSV'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (_failed.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Not created',
              style: TextStyle(color: _red, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._failed.entries.map((e) => _rowTile(e.key, '', e.value, _red)),
        ],
        if (created.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Created',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...created.map((c) => _rowTile(
                c.idNumber,
                c.fullName,
                'Password: ${c.password}'
                '${c.email == null ? '' : '\nEmail: ${c.email}'}',
                _green,
                trailing: c.email == null
                    ? IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.share_rounded, color: _muted),
                        onPressed: () => shareCredentials(c),
                      )
                    : IconButton(
                        tooltip: 'Send to ${c.email}',
                        icon: const Icon(Icons.email_outlined, color: _accent),
                        onPressed: () => sendCredentialsTo(c.email!, c),
                      ),
              )),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => setState(() {
            _fileName = null;
            _rows = [];
            _created = null;
            _failed = {};
          }),
          child: const Text('Import another file',
              style: TextStyle(color: _accent)),
        ),
      ],
    );
  }

  Widget _rowTile(String id, String name, String detail, Color detailColor,
      {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? id : '$name  •  $id',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                SelectableText(detail,
                    style: TextStyle(color: detailColor, fontSize: 11.5)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  static String _roleName(String role) => switch (role) {
        'admin' => 'Administrator',
        'instructor' => 'Faculty',
        _ => 'Student',
      };
}
