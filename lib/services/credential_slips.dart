import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Login details handed to a student or faculty member.
class AccountCredentials {
  const AccountCredentials({
    required this.fullName,
    required this.idNumber,
    required this.password,
    this.email,
  });

  final String fullName;
  final String idNumber;
  final String password;

  /// Where the login details can be emailed (optional).
  final String? email;

  String get shareText => 'Your Edushelf account\n'
      'Name: $fullName\n'
      'ID Number: $idNumber\n'
      'Temporary password: $password\n\n'
      'Log in with your ID number and this password. You will be asked to '
      'set your own password right away.';
}

/// Credentials as CSV, for the admin's records.
String credentialsToCsv(List<AccountCredentials> list) {
  String cell(String v) =>
      RegExp(r'[",\r\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
  final rows = [
    'id_number,full_name,temporary_password,email',
    for (final c in list)
      [c.idNumber, c.fullName, c.password, c.email ?? ''].map(cell).join(','),
  ];
  return '${rows.join('\r\n')}\r\n';
}

/// A4 PDF of cut-out login slips, 8 per page (2 columns x 4 rows).
Future<Uint8List> buildCredentialSlipsPdf(List<AccountCredentials> list) async {
  final doc = pw.Document(title: 'Edushelf login slips', author: 'Edushelf');
  const perPage = 8;

  for (var start = 0; start < list.length; start += perPage) {
    final page = list.sublist(
        start, start + perPage > list.length ? list.length : start + perPage);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.GridView(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          children: [for (final c in page) _slip(c)],
        ),
      ),
    );
  }
  return doc.save();
}

pw.Widget _slip(AccountCredentials c) {
  const grey = PdfColor.fromInt(0xFF64748B);
  const blue = PdfColor.fromInt(0xFF1D4ED8);

  pw.Widget row(String label, String value, {bool mono = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: grey)),
            pw.Text(value,
                style: pw.TextStyle(
                  fontSize: mono ? 14 : 11,
                  fontWeight: pw.FontWeight.bold,
                  font: mono ? pw.Font.courierBold() : null,
                )),
          ],
        ),
      );

  return pw.Container(
    margin: const pw.EdgeInsets.all(4),
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(
          color: PdfColors.grey500, width: 0.8, style: pw.BorderStyle.dashed),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('EDUSHELF ACCOUNT',
            style: const pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: blue,
                letterSpacing: 1)),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        row('Name', c.fullName),
        row('ID Number', c.idNumber, mono: true),
        row('Temporary Password', c.password, mono: true),
        pw.Spacer(),
        pw.Text(
          'Log in with your ID number and this password. You will be asked '
          'to set your own password. Keep this slip private.',
          style: const pw.TextStyle(fontSize: 7.5, color: grey),
        ),
      ],
    ),
  );
}
