import '../models/rental.dart';

/// Base charge for the planned slot (not including overtime penalty).
double baseRentalCost(Rental r) =>
    (r.plannedMinutes / 60.0) * r.ratePerHour;

/// Ride length in minutes from approval to [at]. Wait time is not counted.
double rideElapsedMinutes(Rental r, DateTime at) {
  final start = r.approvedAt;
  if (start == null) return 0;
  return at.difference(start).inSeconds / 60.0;
}

/// Minutes beyond the planned window (0 if returned on time or early).
double overtimeMinutesAt(Rental r, DateTime at) {
  final elapsed = rideElapsedMinutes(r, at);
  return (elapsed - r.plannedMinutes).clamp(0.0, double.infinity);
}

double penaltyForOvertimeMinutes(Rental r, double overtimeMin) =>
    (overtimeMin / 60.0) * r.ratePerHour * 1.5;

double suggestedTotalAt(Rental r, DateTime at) =>
    baseRentalCost(r) + penaltyForOvertimeMinutes(r, overtimeMinutesAt(r, at));

String formatRideDurationMinutes(double minutes) {
  final m = minutes.round();
  if (m <= 0) return '0m';
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  final min = m % 60;
  if (h < 24) {
    return min == 0 ? '${h}h' : '${h}h ${min}m';
  }
  final d = h ~/ 24;
  final hr = h % 24;
  if (min == 0 && hr == 0) return '${d}d';
  if (min == 0) return '${d}d ${hr}h';
  return '${d}d ${hr}h ${min}m';
}
