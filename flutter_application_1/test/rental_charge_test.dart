import 'package:flutter_application_1/models/rental.dart';
import 'package:flutter_application_1/utils/rental_billing.dart';
import 'package:flutter_test/flutter_test.dart';

Rental _ride({
  required DateTime start,
  required int minutes,
  required double rate,
  double? estimated,
  double? actual,
  double? penalty,
  String status = 'active',
  DateTime? endedAt,
}) {
  return Rental(
    id: 'r1',
    bikeId: 'b1',
    userId: 'u1',
    startedAt: start,
    approvedAt: start,
    endedAt: endedAt,
    status: status,
    plannedMinutes: minutes,
    ratePerHour: rate,
    estimatedCost: estimated,
    actualCost: actual,
    penaltyFee: penalty,
  );
}

void main() {
  final start = DateTime.utc(2026, 10, 1, 2);

  test('a fee change mid-ride prices only the later part at the new fee', () {
    final history = [
      HourlyRateChange(
        effectiveAt: start.add(const Duration(hours: 1)),
        ratePerHour: 80,
      ),
    ];
    final charge = rentalChargeAt(
      _ride(start: start, minutes: 120, rate: 50, estimated: 100),
      start.add(const Duration(hours: 2)),
      history,
    );

    expect(charge.base, 130);
    expect(charge.penalty, 0);
    expect(charge.total, 130);
  });

  test('overtime after a fee change uses the new fee at 1.5x', () {
    final history = [
      HourlyRateChange(
        effectiveAt: start.add(const Duration(hours: 1)),
        ratePerHour: 80,
      ),
    ];
    final charge = rentalChargeAt(
      _ride(start: start, minutes: 120, rate: 50, estimated: 100),
      start.add(const Duration(hours: 2, minutes: 30)),
      history,
    );

    expect(charge.base, 130);
    expect(charge.penalty, 60);
    expect(charge.total, 190);
  });

  test('a fee change after the ride ended does not reprice it', () {
    final ended = start.add(const Duration(hours: 1));
    final history = [
      HourlyRateChange(
        effectiveAt: ended.add(const Duration(hours: 2)),
        ratePerHour: 80,
      ),
    ];
    final ride = _ride(
      start: start,
      minutes: 60,
      rate: 50,
      estimated: 50,
      actual: 50,
      status: 'ended',
      endedAt: ended,
    );

    expect(rentalChargeAt(ride, ended, history).total, 50);
    expect(collectedAmount(ride), 50);
  });

  test('collected uses the saved total and does not add the penalty again', () {
    final ride = _ride(
      start: start,
      minutes: 60,
      rate: 50,
      estimated: 50,
      actual: 110,
      penalty: 60,
      status: 'ended',
      endedAt: start.add(const Duration(hours: 1, minutes: 30)),
    );

    expect(collectedAmount(ride), 110);
  });

  test('without history the saved estimate is kept', () {
    final charge = rentalChargeAt(
      _ride(start: start, minutes: 120, rate: 50, estimated: 100),
      start.add(const Duration(hours: 2)),
      const [],
    );

    expect(charge.base, 100);
    expect(charge.penalty, 0);
  });
}
