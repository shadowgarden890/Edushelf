import '../models/user_session.dart';

/// Parses CSV text (RFC 4180: quoted fields, "" escapes, CRLF or LF).
List<List<String>> parseCsv(String text) {
  if (text.startsWith('﻿')) text = text.substring(1); // Excel BOM

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// One row of an import file, after checking.
class ImportRow {
  ImportRow({
    required this.line,
    required this.idNumber,
    required this.fullName,
    this.email,
    this.error,
  });

  final int line; // line number in the file, for error messages
  final String idNumber;
  final String fullName;

  /// Optional; the login details can be emailed to it.
  final String? email;
  final String? error;

  bool get isValid => error == null;
  Map<String, String>? get parsed => UserSession.parseId(idNumber);
}

const _idHeaders = {
  'id_number',
  'id number',
  'idnumber',
  'id',
  'id no',
  'id no.',
  'student id',
  'student_id',
  'employee id',
  'faculty id',
  'school id',
};
const _emailHeaders = {
  'email',
  'e-mail',
  'email address',
  'e-mail address',
  'emailaddress',
};

/// A simple email check (something@domain.tld).
bool isValidEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

const _nameHeaders = {
  'full_name',
  'full name',
  'fullname',
  'name',
  'student name',
  'faculty name',
};

/// Reads accounts from CSV. Columns are found by header (e.g. "ID Number",
/// "Full Name", optional "Email"); without a header row, column 1 is the
/// ID, column 2 the name and column 3 (optional) the email. Each row is
/// checked for format, missing names, bad emails and duplicates.
List<ImportRow> readAccountsCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return [];

  var idCol = 0;
  var nameCol = 1;
  var emailCol = 2;
  var first = 0;

  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  final headerId = header.indexWhere(_idHeaders.contains);
  final headerName = header.indexWhere(_nameHeaders.contains);
  if (headerId >= 0 && headerName >= 0) {
    idCol = headerId;
    nameCol = headerName;
    emailCol = header.indexWhere(_emailHeaders.contains); // -1 = no column
    first = 1;
  }

  final seen = <String>{};
  final result = <ImportRow>[];
  for (var i = first; i < rows.length; i++) {
    final r = rows[i];
    final id = (idCol < r.length ? r[idCol] : '').trim().toUpperCase();
    final name = (nameCol < r.length ? r[nameCol] : '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');

    final emailText =
        emailCol >= 0 && emailCol < r.length ? r[emailCol].trim() : '';

    String? error;
    if (id.isEmpty) {
      error = 'Missing ID number';
    } else if (UserSession.parseId(id) == null) {
      error = 'Invalid ID format';
    } else if (name.isEmpty) {
      error = 'Missing full name';
    } else if (name.length > 120) {
      error = 'Name is too long';
    } else if (emailText.isNotEmpty && !isValidEmail(emailText)) {
      error = 'Invalid email "$emailText"';
    } else if (!seen.add(id)) {
      error = 'Duplicate ID in this file';
    }

    result.add(ImportRow(
        line: i + 1,
        idNumber: id,
        fullName: name,
        email: emailText.isEmpty ? null : emailText,
        error: error));
  }
  return result;
}

/// Example file the admin can fill in.
const accountsCsvTemplate = 'ID Number,Full Name,Email\r\n'
    'IT-23-01003,Juan Dela Cruz,juan.delacruz@example.com\r\n'
    'BA-24-00015,Maria Santos,\r\n'
    'IT-T-00002,Prof. Ana Reyes,ana.reyes@example.com\r\n';
