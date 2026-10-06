import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/register_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The login backdrop animates forever, so step frames instead of settling.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('name first, then username above password, back keeps input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const RegisterScreen()),
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await _frames(tester);

    expect(find.text('About you'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Username'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await _frames(tester);
    expect(find.text('First name is required'), findsOneWidget);
    expect(find.text('About you'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Juan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name'),
      'Dela Cruz',
    );

    final year = DateTime.now().year - 20;
    Finder inGrid(String text) =>
        find.descendant(of: find.byType(GridView), matching: find.text(text));
    await tester.tap(find.widgetWithText(TextFormField, 'Birthdate'));
    await _frames(tester);
    await tester.tap(inGrid('$year'));
    await _frames(tester);
    await tester.tap(inGrid('March'));
    await _frames(tester);
    await tester.tap(inGrid('14'));
    await _frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await _frames(tester);
    expect(find.text('$year-03-14'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await _frames(tester);
    expect(find.text('Your account'), findsOneWidget);

    double top(String label) =>
        tester.getTopLeft(find.widgetWithText(TextFormField, label)).dy;
    expect(top('Username'), lessThan(top('Password')));
    expect(top('Password'), lessThan(top('Confirm password')));
    expect(top('Confirm password'), lessThan(top('Email address')));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'juan_dc',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'ride2',
    );
    await _frames(tester);
    expect(find.text('Use at least 6 characters'), findsNothing);
    expect(find.text('Please confirm your password'), findsNothing);
    expect(find.text('Email is required'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await _frames(tester);
    expect(find.text('Use at least 6 characters'), findsOneWidget);
    expect(find.text('Please confirm your password'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Your account'), findsOneWidget);

    await tester.pageBack();
    await _frames(tester);
    expect(find.text('About you'), findsOneWidget);
    expect(find.text('Juan'), findsOneWidget);
    expect(find.text('$year-03-14'), findsOneWidget);

    await tester.pageBack();
    await _frames(tester);
    expect(find.text('go'), findsOneWidget);
  });
}
