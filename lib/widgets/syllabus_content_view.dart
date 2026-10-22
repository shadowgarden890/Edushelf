import 'package:flutter/material.dart';

import '../models/syllabus_content.dart';

const _card = Color(0xFF1C2541);
const _muted = Color(0xFF94A3B8);
const _accent = Color(0xFF38BDF8);

/// A syllabus entered as content: collapsible year/semester sections with
/// course tables and unit totals. [query] filters to matching courses
/// (by code or title) so students can find a subject to take in advance.
class SyllabusContentView extends StatelessWidget {
  const SyllabusContentView({
    super.key,
    required this.content,
    required this.header,
    this.query = '',
    this.textScale = 1.0,
  });

  final SyllabusContent content;
  final Widget header;
  final String query;
  final double textScale;

  bool _matches(SyllabusCourse c, String q) =>
      c.code.toLowerCase().contains(q) || c.title.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final searching = q.isNotEmpty;

    final sections = [
      for (final s in content.sections)
        (
          section: s,
          courses: searching
              ? s.courses.where((c) => _matches(c, q)).toList()
              : s.courses,
        ),
    ].where((e) => !searching || e.courses.isNotEmpty).toList();

    final found = sections.fold<int>(0, (n, e) => n + e.courses.length);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        header,
        if (content.programTitle.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(content.programTitle,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15 * textScale)),
        ],
        if (content.notes.isNotEmpty && !searching) ...[
          const SizedBox(height: 10),
          _NotesBox(notes: content.notes, textScale: textScale),
        ],
        const SizedBox(height: 14),
        Text(
          searching
              ? (found == 0
                  ? 'No course matches "$query".'
                  : '$found course${found == 1 ? '' : 's'} found')
              : '${content.sections.length} semesters • '
                  '${content.courseCount} courses • '
                  '${formatUnits(content.totalUnits)} units',
          style: const TextStyle(color: _muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < sections.length; i++)
          _SectionTile(
            // A new key per search re-opens the matching sections.
            key: ValueKey('${sections[i].section.title}|$q'),
            section: sections[i].section,
            courses: sections[i].courses,
            initiallyExpanded: searching || i == 0,
            highlight: q,
            textScale: textScale,
          ),
        if (!searching && content.sections.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Total units: ${formatUnits(content.totalUnits)}',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14 * textScale)),
          ),
        ],
      ],
    );
  }
}

class _NotesBox extends StatelessWidget {
  const _NotesBox({required this.notes, required this.textScale});

  final String notes;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x55FBBF24)),
      ),
      child: SelectableText(notes,
          style: TextStyle(
              color: const Color(0xFFFDE68A),
              fontSize: 12 * textScale,
              height: 1.45)),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    super.key,
    required this.section,
    required this.courses,
    required this.initiallyExpanded,
    required this.highlight,
    required this.textScale,
  });

  final SyllabusSection section;
  final List<SyllabusCourse> courses;
  final bool initiallyExpanded;
  final String highlight;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            iconColor: _accent,
            collapsedIconColor: _muted,
            title: Text(section.title,
                style: TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14 * textScale)),
            subtitle: Text(
                '${section.courses.length} courses • '
                '${formatUnits(section.totalUnits)} units',
                style: const TextStyle(color: _muted, fontSize: 11.5)),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                        width: 84 * textScale,
                        child: const Text('CODE',
                            style: TextStyle(
                                color: _muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold))),
                    const Expanded(
                        child: Text('COURSE TITLE',
                            style: TextStyle(
                                color: _muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold))),
                    const Text('UNITS',
                        style: TextStyle(
                            color: _muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              for (final c in courses) _courseRow(c),
              const Divider(color: Color(0xFF334155), height: 14),
              Row(
                children: [
                  const Spacer(),
                  Text('Total  ${formatUnits(section.totalUnits)}',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13 * textScale)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _courseRow(SyllabusCourse c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF253354))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84 * textScale,
            child: SelectableText.rich(_mark(
                c.code,
                TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13 * textScale))),
          ),
          Expanded(
            child: SelectableText.rich(_mark(
                c.title,
                TextStyle(
                    color: const Color(0xFFE2E8F0),
                    fontSize: 13 * textScale,
                    height: 1.35))),
          ),
          const SizedBox(width: 8),
          Text(formatUnits(c.units),
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13 * textScale)),
        ],
      ),
    );
  }

  /// [text] with the search term highlighted.
  TextSpan _mark(String text, TextStyle style) {
    if (highlight.isEmpty) return TextSpan(text: text, style: style);
    final i = text.toLowerCase().indexOf(highlight);
    if (i < 0) return TextSpan(text: text, style: style);
    return TextSpan(style: style, children: [
      TextSpan(text: text.substring(0, i)),
      TextSpan(
        text: text.substring(i, i + highlight.length),
        style: const TextStyle(
            backgroundColor: Color(0xFFFBBF24), color: Colors.black),
      ),
      TextSpan(text: text.substring(i + highlight.length)),
    ]);
  }
}
