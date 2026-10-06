import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/user_active_rental_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('extend asks for confirmation and shows the selected cost', (
    tester,
  ) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showModalBottomSheet<int>(
                  context: context,
                  isScrollControlled: true,
                  builder: (ctx) => const ExtendTimeSheet(
                    currentPlannedMinutes: 60,
                    ratePerHour: 20,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Total for 15 min'), findsOneWidget);
    expect(find.text('₱5'), findsOneWidget);

    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();
    expect(find.text('Total for 30 min'), findsOneWidget);
    expect(find.text('₱10'), findsOneWidget);

    await tester.tap(find.text('Extend by 30 min'));
    await tester.pumpAndSettle();
    expect(find.text('The total for this 30 min is ₱10. Your booked time becomes 1h 30m.'), findsOneWidget);

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('Extend by 30 min'), findsOneWidget);

    await tester.tap(find.text('Extend by 30 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(picked, 30);
  });
}
