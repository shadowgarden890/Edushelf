import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// One line of text pulled out of a PDF.
class PdfLine {
  const PdfLine(this.text, this.fontSize, this.bold, this.page);

  final String text;
  final double fontSize;
  final bool bold;
  final int page;
}

/// A heading or a paragraph of the syllabus, ready to show as text.
class SyllabusBlock {
  const SyllabusBlock(this.text, {this.isHeading = false});

  final String text;
  final bool isHeading;
}

/// Reads every text line from a PDF. Runs fine in a background isolate.
/// Returns an empty list for scanned (image-only) PDFs.
List<PdfLine> extractPdfLines(Uint8List bytes) {
  final document = sf.PdfDocument(inputBytes: bytes);
  try {
    return [
      for (final line in sf.PdfTextExtractor(document).extractTextLines())
        if (line.text.trim().isNotEmpty)
          PdfLine(
            line.text.trim(),
            line.fontSize,
            line.fontStyle.contains(sf.PdfFontStyle.bold),
            line.pageIndex,
          ),
    ];
  } finally {
    document.dispose();
  }
}

/// Lines starting a list item ("1.", "a)", "•", "-", "Week 3") begin a new
/// paragraph instead of joining the previous one.
final _listStart = RegExp(
    r'^(\d{1,2}[.)]\s|[a-zA-Z][.)]\s|[•▪◦●\-–*]\s?|week\s*\d+|wk\s*\d+)',
    caseSensitive: false);

/// Groups PDF lines into headings and paragraphs:
/// - headings: noticeably bigger text, or short bold / ALL-CAPS lines;
/// - lines of one paragraph are joined (hyphenated breaks are mended);
/// - list items, page changes and lines ending in ':' start a new block.
List<SyllabusBlock> buildSyllabusBlocks(List<PdfLine> lines) {
  if (lines.isEmpty) return const [];

  // Body text = the font size used by the most characters.
  final charsPerSize = <double, int>{};
  for (final l in lines) {
    final size = (l.fontSize * 2).round() / 2; // group 10.9 / 11.0 etc.
    charsPerSize[size] = (charsPerSize[size] ?? 0) + l.text.length;
  }
  final bodySize =
      charsPerSize.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  bool isHeading(PdfLine l) {
    final t = l.text;
    if (t.length > 90) return false;
    if (l.fontSize >= bodySize * 1.15) return true;
    final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
    final allCaps = letters.length >= 3 && letters == letters.toUpperCase();
    return (l.bold || allCaps) && t.length <= 70 && !t.endsWith(',');
  }

  final blocks = <SyllabusBlock>[];
  final paragraph = StringBuffer();
  int? paragraphPage;

  void flush() {
    final text = paragraph.toString().trim();
    if (text.isNotEmpty) blocks.add(SyllabusBlock(text));
    paragraph.clear();
    paragraphPage = null;
  }

  for (final line in lines) {
    final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (isHeading(line)) {
      flush();
      // Two heading lines in a row (a wrapped title) become one heading.
      if (blocks.isNotEmpty &&
          blocks.last.isHeading &&
          blocks.last.text.length + text.length < 90) {
        blocks[blocks.length - 1] =
            SyllabusBlock('${blocks.last.text} $text', isHeading: true);
      } else {
        blocks.add(SyllabusBlock(text, isHeading: true));
      }
      continue;
    }

    final startsNew = paragraph.isEmpty ||
        paragraphPage != line.page ||
        _listStart.hasMatch(text) ||
        paragraph.toString().trimRight().endsWith(':');
    if (startsNew) flush();

    if (paragraph.isEmpty) {
      paragraph.write(text);
      paragraphPage = line.page;
    } else {
      final current = paragraph.toString();
      if (current.endsWith('-') && !current.endsWith(' -')) {
        // "informa-" + "tion" -> "information"
        paragraph
          ..clear()
          ..write(current.substring(0, current.length - 1))
          ..write(text);
      } else {
        paragraph.write(' $text');
      }
    }
  }
  flush();
  return blocks;
}
