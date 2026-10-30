import 'package:flutter/material.dart';

import '../../models/learning_material.dart';
import '../physical_flipbook_reader.dart';
import '../syllabus_screen.dart';

/// Opens a `materials` row for the admin to look at: syllabi as course
/// tables, PDFs in the reader. Nothing is saved as reading progress.
void previewMaterialRow(BuildContext context, Map<String, dynamic> row) {
  final material = LearningMaterial.fromRow(row);
  if (!material.isSyllabus && !material.hasFile) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF attached to this material.')));
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => material.isSyllabus
          ? SyllabusScreen(material: material)
          : PhysicalFlipbookReader(
              material: material,
              initialPage: 1,
              onProgressSaved: (_) {},
              trackProgress: false,
            ),
    ),
  );
}
