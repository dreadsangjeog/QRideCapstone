import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/kyc/kyc_face_match_panel.dart';
import 'package:flutter_application_1/services/kyc_auto_match_result.dart';
import 'package:flutter_test/flutter_test.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

KycAutoMatchResult _result({KycFaceVerdict? verdict, KycFaceStep? unreadable}) {
  return KycAutoMatchResult(
    nameMatch: true,
    photoMatch: verdict == KycFaceVerdict.match ||
        verdict == KycFaceVerdict.unsure,
    note: 'Note for the rider',
    faceVerdict: verdict,
    faceScore: verdict == null ? null : 0.6,
    unreadable: unreadable,
  );
}

/// Runs the three scripted steps, then shows [outcome].
Future<List<KycAutoMatchResult>> _pumpToResult(
  WidgetTester tester,
  KycAutoMatchResult outcome,
) async {
  final finished = <KycAutoMatchResult>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: KycFaceMatchPanel(
          idPhoto: _pixel,
          selfie: _pixel,
          work: Future.value(outcome),
          onFinished: finished.add,
        ),
      ),
    ),
  );
  expect(find.text('Matching faces'), findsOneWidget);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 640));
  }
  await tester.pump();
  // Let the title cross-fade finish.
  await tester.pump(const Duration(milliseconds: 300));
  return finished;
}

void main() {
  testWidgets('a match says so and moves on after a short pause', (
    tester,
  ) async {
    final outcome = _result(verdict: KycFaceVerdict.match);
    final finished = await _pumpToResult(tester, outcome);

    expect(find.text('Faces match'), findsOneWidget);
    expect(find.text('Strong match'), findsOneWidget);
    expect(find.text('Note for the rider'), findsOneWidget);
    expect(finished, isEmpty);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(finished, [outcome]);
  });

  testWidgets('an unsure result is sent to staff and held longer', (
    tester,
  ) async {
    final outcome = _result(verdict: KycFaceVerdict.unsure);
    final finished = await _pumpToResult(tester, outcome);

    expect(find.text('Sent to staff'), findsOneWidget);
    expect(find.text('Staff will compare'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(finished, isEmpty);
    await tester.pump(const Duration(milliseconds: 900));
    expect(finished, [outcome]);
  });

  testWidgets('a mismatch is shown as no match', (tester) async {
    final outcome = _result(verdict: KycFaceVerdict.mismatch);
    final finished = await _pumpToResult(tester, outcome);

    expect(find.text('Faces did not match'), findsOneWidget);
    expect(find.text('No match'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    expect(finished, [outcome]);
  });

  testWidgets('an unreadable selfie names the step that failed', (
    tester,
  ) async {
    final outcome = _result(unreadable: KycFaceStep.liveSelfie);
    final finished = await _pumpToResult(tester, outcome);

    expect(find.text('Selfie not clear'), findsOneWidget);
    expect(find.text('Strong match'), findsNothing);
    expect(find.text('Staff will compare'), findsNothing);
    expect(find.text('No match'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2200));
    expect(finished, [outcome]);
  });
}
