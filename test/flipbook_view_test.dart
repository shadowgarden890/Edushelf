import 'dart:convert';

import 'package:edushelf_reading_application/widgets/flipbook_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 white PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=');

void main() {
  late List<int> changes;
  late GlobalKey<FlipbookViewState> key;

  Future<void> pumpBook(WidgetTester tester, {int initialPage = 1}) async {
    changes = [];
    key = GlobalKey<FlipbookViewState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FlipbookView(
          key: key,
          pageCount: 5,
          initialPage: initialPage,
          loadPage: (_) async => FlipbookPage(_png, 0.7),
          onPageChanged: changes.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('flipNext and flipPrevious turn pages', (tester) async {
    await pumpBook(tester);

    key.currentState!.flipNext();
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 2);

    key.currentState!.flipPrevious();
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 1);
    expect(changes, [2, 1]);
  });

  testWidgets('does not turn past the first or last page', (tester) async {
    await pumpBook(tester);
    key.currentState!.flipPrevious();
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 1);

    await pumpBook(tester, initialPage: 5);
    key.currentState!.flipNext();
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 5);
    expect(changes, isEmpty);
  });

  testWidgets('dragging left far enough turns forward', (tester) async {
    await pumpBook(tester, initialPage: 2);

    await tester.drag(find.byType(FlipbookView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 3);
  });

  testWidgets('a short drag springs back without turning', (tester) async {
    await pumpBook(tester, initialPage: 2);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(FlipbookView)));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(-10, 0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 2);
    expect(changes, isEmpty);
  });

  testWidgets('tapping the right or left side turns the page', (tester) async {
    await pumpBook(tester, initialPage: 3);
    final rect = tester.getRect(find.byType(FlipbookView));

    await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 4);

    await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
    await tester.pumpAndSettle();
    expect(key.currentState!.page, 3);
  });
}
