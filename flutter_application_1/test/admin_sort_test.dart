import 'package:flutter_application_1/models/bike.dart';
import 'package:flutter_application_1/models/rental.dart';
import 'package:flutter_application_1/utils/admin_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('natural order puts Bike 2 before Bike 10', () {
    final names = ['Bike 10', 'Bike 2', 'bike 1'];
    names.sort(compareNatural);
    expect(names, ['bike 1', 'Bike 2', 'Bike 10']);
  });

  test('bike A–Z uses the label shown on the card', () {
    final bikes = [
      Bike(id: '1', code: 'ZZZ', status: 'available', label: 'Bike 2'),
      Bike(id: '2', code: 'AAA', status: 'available', label: 'Bike 10'),
    ]..sort((a, b) => compareNatural(bikeSortName(a), bikeSortName(b)));
    expect(bikes.map((b) => b.label).toList(), ['Bike 2', 'Bike 10']);
  });

  test('ended history sorts by end time, not request time', () {
    final earlyRequestLateEnd = Rental(
      id: 'a',
      bikeId: 'b',
      startedAt: DateTime.utc(2026, 10, 1),
      endedAt: DateTime.utc(2026, 10, 4),
      status: 'ended',
      plannedMinutes: 60,
      ratePerHour: 20,
    );
    final laterRequestEarlierEnd = Rental(
      id: 'b',
      bikeId: 'b',
      startedAt: DateTime.utc(2026, 10, 3),
      endedAt: DateTime.utc(2026, 10, 3, 12),
      status: 'ended',
      plannedMinutes: 60,
      ratePerHour: 20,
    );
    final rows = [laterRequestEarlierEnd, earlyRequestLateEnd]
      ..sort((a, b) => rentalActivityAt(b).compareTo(rentalActivityAt(a)));
    expect(rows.first.id, 'a');
  });

  test('active rides due sooner come first', () {
    final later = Rental(
      id: 'later',
      bikeId: 'b',
      startedAt: DateTime.utc(2026, 10, 1),
      approvedAt: DateTime.utc(2026, 10, 4, 8),
      status: 'active',
      plannedMinutes: 120,
      ratePerHour: 20,
    );
    final sooner = Rental(
      id: 'sooner',
      bikeId: 'b',
      startedAt: DateTime.utc(2026, 10, 2),
      approvedAt: DateTime.utc(2026, 10, 4, 9),
      status: 'active',
      plannedMinutes: 30,
      ratePerHour: 20,
    );
    final rows = [later, sooner]..sort(compareActiveRentals);
    expect(rows.first.id, 'sooner');
  });
}
