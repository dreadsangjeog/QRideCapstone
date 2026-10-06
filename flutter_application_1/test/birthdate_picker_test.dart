import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/birthdate_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime? picked;

  Future<void> open(
    WidgetTester tester, {
    required DateTime initial,
    bool startWithYear = false,
  }) async {
    picked = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showBirthdatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(1920),
                    lastDate: DateTime(2025, 10, 4),
                    startWithYear: startWithYear,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder inGrid(String text) =>
      find.descendant(of: find.byType(GridView), matching: find.text(text));

  testWidgets('a new birthdate walks year, then month, then day', (
    tester,
  ) async {
    await open(tester, initial: DateTime(2007, 10, 5), startWithYear: true);

    await tester.tap(inGrid('2003'));
    await tester.pumpAndSettle();
    await tester.tap(inGrid('May'));
    await tester.pumpAndSettle();
    await tester.tap(inGrid('17'));
    await tester.pumpAndSettle();
    expect(find.text('May 17, 2003'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2003, 5, 17));
  });

  testWidgets('a year whose month is out of range clamps to the last day', (
    tester,
  ) async {
    await open(tester, initial: DateTime(2024, 12, 20), startWithYear: true);

    await tester.tap(inGrid('2025'));
    await tester.pumpAndSettle();
    expect(find.text('October 4, 2025'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2025, 10, 4));
  });

  testWidgets('a six-week month keeps its last row on a short phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // August 2008 starts on a Friday, so it spans six weeks.
    await open(tester, initial: DateTime(2008, 8, 1));
    await tester.tap(inGrid('31'));
    await tester.pumpAndSettle();
    expect(find.text('August 31, 2008'), findsOneWidget);
  });

  testWidgets('cancel returns nothing', (tester) async {
    await open(tester, initial: DateTime(2008, 8, 1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
