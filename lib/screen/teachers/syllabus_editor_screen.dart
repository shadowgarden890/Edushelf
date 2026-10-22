import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/syllabus_content.dart';
import '../../models/user_session.dart';
import '../../services/file_reader.dart' as reader;
import '../../services/syllabus_text.dart';
import '../../services/upload_service.dart';

const _card = Color(0xFF1C2541);
const _field = Color(0xFF0B132B);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFF38BDF8);

/// Common term names, offered when adding a semester.
const _termNames = [
  'First Year - First Semester',
  'First Year - Second Semester',
  'Second Year - First Semester',
  'Second Year - Second Semester',
  'Third Year - First Semester',
  'Third Year - Second Semester',
  'Third Year - Midyear Term',
  'Fourth Year - First Semester',
  'Fourth Year - Second Semester',
];

/// Faculty enter a syllabus as content: courses (code, title, units)
/// grouped by year and semester. "Fill from PDF" reads a curriculum
/// outline PDF into the tables to check and edit; the PDF isn't stored.
class SyllabusEditorScreen extends StatefulWidget {
  final UserSession session;

  const SyllabusEditorScreen({super.key, required this.session});

  @override
  State<SyllabusEditorScreen> createState() => _SyllabusEditorScreenState();
}

class _CourseRow {
  _CourseRow([SyllabusCourse? c])
      : code = TextEditingController(text: c?.code ?? ''),
        title = TextEditingController(text: c?.title ?? ''),
        units =
            TextEditingController(text: c == null ? '3' : formatUnits(c.units));

  final TextEditingController code;
  final TextEditingController title;
  final TextEditingController units;

  void dispose() {
    code.dispose();
    title.dispose();
    units.dispose();
  }
}

class _SectionRows {
  _SectionRows(String title, [List<SyllabusCourse>? courses])
      : title = TextEditingController(text: title),
        rows = [for (final c in courses ?? <SyllabusCourse>[]) _CourseRow(c)];

  final TextEditingController title;
  final List<_CourseRow> rows;

  void dispose() {
    title.dispose();
    for (final r in rows) {
      r.dispose();
    }
  }
}

class _SyllabusEditorScreenState extends State<SyllabusEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(
      text: '${widget.session.department} Curriculum Outline');
  late final _code =
      TextEditingController(text: '${widget.session.department} SYLLABUS');
  final _programTitle = TextEditingController();
  final _notes = TextEditingController();
  final List<_SectionRows> _sections = [
    _SectionRows(_termNames.first, [])..rows.add(_CourseRow()),
  ];

  bool _readingPdf = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _code.dispose();
    _programTitle.dispose();
    _notes.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  // ================================================
  // FILL FROM PDF
  // ================================================
  Future<void> _fillFromPdf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;

    setState(() => _readingPdf = true);
    try {
      var bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await reader.readFileBytes(file.path!);
      }
      if (bytes == null) throw Exception('Could not read the file');

      final lines = kIsWeb
          ? extractPdfLines(bytes)
          : await compute(extractPdfLines, bytes);
      final content = SyllabusContent.fromPdfLines(lines);
      if (!mounted) return;

      if (content.courseCount == 0) {
        _snack('No course tables were found in that PDF. Please enter the '
            'courses yourself.');
        return;
      }

      setState(() {
        for (final s in _sections) {
          s.dispose();
        }
        _sections
          ..clear()
          ..addAll([
            for (final s in content.sections) _SectionRows(s.title, s.courses)
          ]);
        if (content.programTitle.isNotEmpty) {
          _programTitle.text = content.programTitle;
        }
        _notes.text = content.notes;
      });
      _snack('Filled ${content.courseCount} courses in '
          '${content.sections.length} semesters (${formatUnits(content.totalUnits)} '
          'units). Please check them before submitting.');
    } catch (_) {
      if (mounted) _snack('Could not read that PDF.');
    } finally {
      if (mounted) setState(() => _readingPdf = false);
    }
  }

  // ================================================
  // EDITING
  // ================================================
  void _addSection() {
    final used = _sections.map((s) => s.title.text).toSet();
    final next = _termNames.firstWhere((t) => !used.contains(t),
        orElse: () => 'New Semester');
    setState(() => _sections.add(_SectionRows(next)..rows.add(_CourseRow())));
  }

  void _removeSection(int i) {
    setState(() => _sections.removeAt(i).dispose());
  }

  void _addCourse(_SectionRows s) => setState(() => s.rows.add(_CourseRow()));

  void _removeCourse(_SectionRows s, int i) =>
      setState(() => s.rows.removeAt(i).dispose());

  double _sectionUnits(_SectionRows s) => s.rows
      .fold(0, (sum, r) => sum + (double.tryParse(r.units.text.trim()) ?? 0));

  SyllabusContent _buildContent() => SyllabusContent(
        programTitle: _programTitle.text.trim(),
        notes: _notes.text.trim(),
        sections: [
          for (final s in _sections)
            SyllabusSection(title: s.title.text.trim(), courses: [
              for (final r in s.rows)
                if (r.code.text.trim().isNotEmpty ||
                    r.title.text.trim().isNotEmpty)
                  SyllabusCourse(
                    code: r.code.text.trim(),
                    title: r.title.text.trim(),
                    units: double.tryParse(r.units.text.trim()) ?? 0,
                  ),
            ]),
        ],
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _snack('Please fix the highlighted fields.');
      return;
    }
    final content = _buildContent();
    content.sections.removeWhere((s) => s.courses.isEmpty);
    if (content.courseCount == 0) {
      _snack('Add at least one course.');
      return;
    }

    setState(() => _saving = true);
    final error = await UploadService.submitSyllabus(
      session: widget.session,
      title: _title.text,
      code: _code.text,
      content: content,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      _snack(error);
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Syllabus submitted',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          '${content.courseCount} courses in ${content.sections.length} '
          'semesters were sent to the admin for review. Students will see it '
          'once it is approved.',
          style: const TextStyle(color: _muted, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3A86FF),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ================================================
  // UI
  // ================================================
  @override
  Widget build(BuildContext context) {
    final total = _sections.fold<double>(0, (sum, s) => sum + _sectionUnits(s));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('New Syllabus',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          TextButton.icon(
            onPressed: _readingPdf || _saving ? null : _fillFromPdf,
            icon: _readingPdf
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _accent),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, color: _accent),
            label:
                const Text('Fill from PDF', style: TextStyle(color: _accent)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Enter the courses for each semester, or tap "Fill from '
                    'PDF" to read them from a curriculum outline and then '
                    'check them. Only the content is saved, not the file.',
                    style:
                        TextStyle(color: _muted, fontSize: 12.5, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                _textField(_title, 'Title shown in Browse',
                    required: true, icon: Icons.title),
                const SizedBox(height: 12),
                _textField(_code, 'Short code',
                    required: true, icon: Icons.qr_code_2_outlined),
                const SizedBox(height: 12),
                _textField(
                    _programTitle,
                    'Program (e.g. Bachelor of Science '
                    'in Information Technology)',
                    icon: Icons.school_outlined),
                const SizedBox(height: 12),
                _textField(_notes, 'Notes (optional), e.g. CMO reference',
                    icon: Icons.notes_rounded, maxLines: 4),
                const SizedBox(height: 20),
                for (var i = 0; i < _sections.length; i++) _sectionCard(i),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: Color(0xFF334155)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _addSection,
                  icon: const Icon(Icons.add),
                  label: const Text('Add semester'),
                ),
                const SizedBox(height: 16),
                Text('Total: ${formatUnits(total)} units',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3A86FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(_saving ? 'Submitting...' : 'Submit for Approval',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(int index) {
    final s = _sections[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: s.title,
                  style: const TextStyle(
                      color: _accent, fontWeight: FontWeight.bold),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Name this semester' : null,
                  decoration: const InputDecoration(
                    hintText: 'e.g. First Year - First Semester',
                    hintStyle: TextStyle(color: Color(0xFF475569)),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Text('${formatUnits(_sectionUnits(s))} units',
                  style: const TextStyle(color: _muted, fontSize: 12)),
              IconButton(
                tooltip: 'Remove semester',
                icon:
                    const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                onPressed: () => _removeSection(index),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(right: 44, bottom: 4),
            child: Row(
              children: [
                SizedBox(
                    width: 92,
                    child: Text('Code',
                        style: TextStyle(color: _muted, fontSize: 11))),
                Expanded(
                    child: Text('Course Title',
                        style: TextStyle(color: _muted, fontSize: 11))),
                SizedBox(
                    width: 52,
                    child: Text('Units',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, fontSize: 11))),
              ],
            ),
          ),
          for (var r = 0; r < s.rows.length; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(width: 88, child: _cell(s.rows[r].code, 'IT 111')),
                  const SizedBox(width: 4),
                  Expanded(child: _cell(s.rows[r].title, 'Course title')),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 52,
                    child: _cell(s.rows[r].units, '3',
                        number: true, onChanged: (_) => setState(() {})),
                  ),
                  IconButton(
                    tooltip: 'Remove course',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, color: _muted, size: 18),
                    onPressed: () => _removeCourse(s, r),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addCourse(s),
              icon: const Icon(Icons.add, size: 18, color: _accent),
              label: const Text('Add course', style: TextStyle(color: _accent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(TextEditingController c, String hint,
      {bool number = false, ValueChanged<String>? onChanged}) {
    return TextFormField(
      controller: c,
      onChanged: onChanged,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textAlign: number ? TextAlign.center : TextAlign.start,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      validator: number
          ? (v) =>
              (v ?? '').trim().isEmpty || double.tryParse(v!.trim()) != null
                  ? null
                  : '?'
          : null,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
        filled: true,
        fillColor: _field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _textField(TextEditingController c, String label,
      {bool required = false, IconData? icon, int maxLines = 1}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      validator:
          required ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        prefixIcon:
            icon == null ? null : Icon(icon, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
