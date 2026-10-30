import 'dart:convert';

import 'package:edushelf_reading_application/widgets/flipbook_view.dart';
import 'package:edushelf_reading_application/widgets/vertical_pages_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1x1 white PNG stands in for a rendered page.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=');

void main() {
  testWidgets('opens on the given page and reports pages while scrolling',
      (tester) async {
    final loaded = <int>{};
    final changes = <int>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerticalPagesView(
          pageCount: 10,
          initialPage: 5,
          aspectRatio: 0.7,
          loadPage: (p) async {
            loaded.add(p);
            return FlipbookPage(_png, 0.7);
          },
          onPageChanged: changes.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(loaded, contains(5), reason: 'starts at the requested page');
    expect(loaded, isNot(contains(1)));

    // Scroll to the very bottom: the last page counts as open.
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(changes.last, 10);
    expect(loaded, contains(10));
  });
}
