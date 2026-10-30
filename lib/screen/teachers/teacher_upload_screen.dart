import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/user_session.dart';
import 'syllabus_editor_screen.dart';
import '../../services/upload_service.dart';

class TeacherUploadScreen extends StatefulWidget {
  final UserSession session;

  /// Called from the success screen's "Back to Dashboard".
  final VoidCallback? onBackToDashboard;

  const TeacherUploadScreen(
      {super.key, required this.session, this.onBackToDashboard});

  @override
  State<TeacherUploadScreen> createState() => _TeacherUploadScreenState();
}

class _TeacherUploadScreenState extends State<TeacherUploadScreen> {
  final _titleController = TextEditingController();
  final _codeController = TextEditingController();

  String _selectedType = 'learning_material';
  String _selectedYear = '1st Year';
  String _selectedTerm = '1st Sem';
  bool _isLoading = false;
  bool _isDragging = false;
  PlatformFile? _selectedFile;

  final List<String> _years = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
  ];

  final List<String> _terms = ['1st Sem', '2nd Sem', 'Summer'];

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ================================================
  // PICK FILE
  // ================================================
  Future<void> _pickFile() async {
    final file = await UploadService.pickPdf();
    if (file == null) return;

    if (!UploadService.isPdf(file)) {
      _showMessage('Only PDF files are allowed.', isError: true);
      return;
    }

    setState(() => _selectedFile = file);
  }

  void _removeFile() {
    setState(() => _selectedFile = null);
  }

  // ================================================
  // SUBMIT
  // ================================================
  Future<void> _handleSubmit() async {
    // "Correct file credentials?" - otherwise ask to revise them.
    final problems = UploadService.checkCredentials(
      file: _selectedFile,
      title: _titleController.text,
      code: _codeController.text,
    );
    if (problems.isNotEmpty) {
      _showReviseDialog(problems);
      return;
    }

    setState(() => _isLoading = true);

    final result = await UploadService.submitMaterial(
      session: widget.session,
      title: _titleController.text.trim(),
      code: _codeController.text.trim(),
      year: _selectedYear,
      term: _selectedTerm,
      type: _selectedType,
      file: _selectedFile!,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success'] == true) {
      _showThankYouDialog();
    } else {
      _showMessage(result['message'] ?? 'Upload failed.', isError: true);
    }
  }

  void _showReviseDialog(List<String> problems) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Color(0xFFFBBF24)),
            SizedBox(width: 10),
            Text('Revise File Credentials',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in problems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $p',
                    style:
                        const TextStyle(color: Color(0xFF94A3B8), height: 1.4)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
        ],
      ),
    );
  }

  // ================================================
  // THANK YOU DIALOG
  // ================================================
  void _showThankYouDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2541),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF22C55E), size: 60),
            const SizedBox(height: 16),
            const Text(
              'Thank You!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "We'll notify you once the review is done.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3A86FF),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _titleController.clear();
                _codeController.clear();
                setState(() => _selectedFile = null);
                widget.onBackToDashboard?.call();
              },
              child: const Text('Back to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Upload Learning Materials',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),

        // Type selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2541),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _buildTypeButton('learning_material', 'Learning Material'),
              _buildTypeButton('syllabus', 'Syllabus'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Syllabi are entered as content; learning materials are PDFs.
        if (_selectedType == 'syllabus')
          ..._buildSyllabusEntry()
        else ...[
          // Drop zone
          _buildDropZone(),
          const SizedBox(height: 20),

          _buildField(_titleController, 'Title', Icons.title),
          const SizedBox(height: 14),
          _buildField(_codeController, 'Course Code', Icons.qr_code_2_outlined),
          const SizedBox(height: 14),

          // Program display
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2541),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.school_outlined,
                    color: Color(0xFF94A3B8), size: 20),
                const SizedBox(width: 12),
                Text(
                  'Program: ${widget.session.department}',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _buildDropdown(
            label: 'Year Level',
            value: _selectedYear,
            items: _years,
            onChanged: (v) => setState(() => _selectedYear = v!),
          ),
          const SizedBox(height: 14),

          _buildDropdown(
            label: 'Term',
            value: _selectedTerm,
            items: _terms,
            onChanged: (v) => setState(() => _selectedTerm = v!),
          ),
          const SizedBox(height: 24),

          // Submit button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3A86FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _isLoading ? null : _handleSubmit,
            icon: _isLoading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_rounded),
            label: Text(
              _isLoading ? 'Uploading...' : 'Submit for Approval',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  // ================================================
  // SYLLABUS (content, no file)
  // ================================================
  List<Widget> _buildSyllabusEntry() => [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2541),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.table_chart_outlined, color: Color(0xFF38BDF8)),
                  SizedBox(width: 10),
                  Text('Syllabus as content',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'A syllabus is not uploaded as a file. Enter its courses '
                '(code, title, units) for each year and semester, or fill '
                'them in from a curriculum outline PDF and check them. '
                'Students can open it freely once the admin approves it.',
                style: TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3A86FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            final submitted = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      SyllabusEditorScreen(session: widget.session)),
            );
            if (submitted == true) widget.onBackToDashboard?.call();
          },
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Create Syllabus',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      ];

  // ================================================
  // DROP ZONE
  // ================================================
  Widget _buildDropZone() {
    // Accepts files dragged from File Explorer / Finder (desktop), as well
    // as picking with Browse Files.
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) async {
        setState(() => _isDragging = false);
        if (details.files.isEmpty) return;
        if (details.files.length > 1) {
          _showMessage('Drop one PDF at a time.', isError: true);
          return;
        }
        final dropped = details.files.first;
        final file = PlatformFile(
          name: dropped.name,
          size: await dropped.length(),
          path: kIsWeb ? null : dropped.path,
          bytes: kIsWeb ? await dropped.readAsBytes() : null,
        );
        if (!UploadService.isPdf(file)) {
          _showMessage('Only PDF files are allowed.', isError: true);
          return;
        }
        setState(() => _selectedFile = file);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 200,
        decoration: BoxDecoration(
          color: _isDragging
              ? const Color(0xFF3A86FF).withValues(alpha: 0.15)
              : const Color(0xFF1C2541),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                _isDragging ? const Color(0xFF38BDF8) : const Color(0xFF334155),
            width: _isDragging ? 2 : 1,
          ),
        ),
        child: _selectedFile == null
            ? _buildEmptyDropContent()
            : _buildSelectedFileContent(),
      ),
    );
  }

  Widget _buildEmptyDropContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isDragging
                ? Icons.file_download_rounded
                : Icons.cloud_upload_outlined,
            size: 52,
            color:
                _isDragging ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
          ),
          const SizedBox(height: 12),
          Text(
            _isDragging ? 'Drop your PDF here' : 'Drag or Drop File',
            style: TextStyle(
              color: _isDragging ? const Color(0xFF38BDF8) : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text('or',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open_rounded,
                size: 18, color: Color(0xFF38BDF8)),
            label: const Text(
              'Browse Files',
              style: TextStyle(
                color: Color(0xFF38BDF8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text('PDF files only',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSelectedFileContent() {
    final file = _selectedFile!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_rounded,
              size: 52, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(
            file.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            UploadService.formatFileSize(file.size),
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.refresh_rounded,
                    size: 18, color: Color(0xFF38BDF8)),
                label: const Text('Replace',
                    style: TextStyle(color: Color(0xFF38BDF8))),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _removeFile,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: Color(0xFFEF4444)),
                label: const Text('Remove',
                    style: TextStyle(color: Color(0xFFEF4444))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================================================
  // HELPERS
  // ================================================
  Widget _buildTypeButton(String value, String label) {
    final isSelected = _selectedType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3A86FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFF1C2541),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        dropdownColor: const Color(0xFF1C2541),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
          border: InputBorder.none,
        ),
        items: items
            .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: const TextStyle(color: Colors.white)),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
