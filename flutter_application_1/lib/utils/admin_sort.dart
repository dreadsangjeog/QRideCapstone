import '../models/bike.dart';
import '../models/rental.dart';

/// Name shown on a bike card. A–Z must follow this, not the raw code alone.
String bikeSortName(Bike bike) {
  final label = bike.label?.trim() ?? '';
  return label.isEmpty ? bike.code : label;
}

/// Case-insensitive order that treats numbers as numbers (`Bike 2` before `Bike 10`).
int compareNatural(String a, String b) {
  final left = _chunks(a);
  final right = _chunks(b);
  final n = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < n; i++) {
    final sa = left[i];
    final sb = right[i];
    final na = int.tryParse(sa);
    final nb = int.tryParse(sb);
    final cmp = (na != null && nb != null) ? na.compareTo(nb) : sa.compareTo(sb);
    if (cmp != 0) return cmp;
  }
  return left.length.compareTo(right.length);
}

List<String> _chunks(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(value.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
}

/// Moment the history row is “newest” by: the latest thing that happened
/// on the rental. Ended rows show [Rental.endedAt], so that must win over
/// the original request time.
DateTime rentalActivityAt(Rental rental) {
  var at = rental.startedAt;
  final approved = rental.approvedAt;
  final ended = rental.endedAt;
  if (approved != null && approved.isAfter(at)) at = approved;
  if (ended != null && ended.isAfter(at)) at = ended;
  return at;
}

/// When this active ride is due. Missing approval sorts first so staff
/// can see rides whose timer has not started.
DateTime? activeDueAt(Rental rental) {
  final start = rental.approvedAt;
  if (start == null) return null;
  return start.add(Duration(minutes: rental.plannedMinutes));
}

int compareActiveRentals(Rental a, Rental b) {
  final aDue = activeDueAt(a);
  final bDue = activeDueAt(b);
  if (aDue == null && bDue == null) {
    return b.startedAt.compareTo(a.startedAt);
  }
  if (aDue == null) return -1;
  if (bDue == null) return 1;
  final byDue = aDue.compareTo(bDue);
  if (byDue != 0) return byDue;
  return a.id.compareTo(b.id);
}
