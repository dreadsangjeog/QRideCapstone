import '../models/rental.dart';
import 'peso.dart';

/// One saved hourly fee and the instant it started applying.
class HourlyRateChange {
  const HourlyRateChange({
    required this.effectiveAt,
    required this.ratePerHour,
  });

  final DateTime effectiveAt;
  final double ratePerHour;
}

class RentalCharge {
  const RentalCharge({required this.base, required this.penalty});

  final double base;
  final double penalty;

  double get total => roundPeso(base + penalty);
}

DateTime _utc(DateTime t) => t.isUtc ? t : t.toUtc();

/// Fee in effect at [at]. Times before the first saved change use [quotedRate].
double rateAt(
  DateTime at,
  List<HourlyRateChange> history,
  double quotedRate,
) {
  final moment = _utc(at);
  double? rate;
  DateTime? chosen;
  for (final change in history) {
    final when = _utc(change.effectiveAt);
    if (when.isAfter(moment)) continue;
    if (chosen == null || when.isAfter(chosen)) {
      chosen = when;
      rate = change.ratePerHour;
    }
  }
  final found = rate;
  if (found == null || found <= 0) return quotedRate;
  return found;
}

double _integrateHours({
  required DateTime from,
  required DateTime to,
  required double quotedRate,
  required List<HourlyRateChange> history,
  double multiplier = 1,
}) {
  final start = _utc(from);
  final end = _utc(to);
  if (!end.isAfter(start)) return 0;
  final cuts = <DateTime>[start, end];
  for (final change in history) {
    final when = _utc(change.effectiveAt);
    if (when.isAfter(start) && when.isBefore(end)) cuts.add(when);
  }
  cuts.sort();
  var sum = 0.0;
  for (var i = 0; i < cuts.length - 1; i++) {
    final a = cuts[i];
    final b = cuts[i + 1];
    final hours = b.difference(a).inMicroseconds / 3600000000.0;
    sum += hours * rateAt(a, history, quotedRate) * multiplier;
  }
  return sum;
}

/// Full booked slot. Ending early does not drop minutes.
///
/// With no rate history, the saved estimate is kept. After a fee change,
/// each part of the slot uses the fee in effect during that part.
double slotCharge({
  required DateTime? planStart,
  required int plannedMinutes,
  required double quotedRate,
  required List<HourlyRateChange> history,
  DateTime? now,
  double? estimatedCost,
}) {
  if (history.isEmpty) {
    return roundPeso(estimatedCost ?? (plannedMinutes / 60.0) * quotedRate);
  }
  final at = now ?? DateTime.now();
  if (planStart == null) {
    return roundPeso((plannedMinutes / 60.0) * rateAt(at, history, quotedRate));
  }
  final planEnd = planStart.add(Duration(minutes: plannedMinutes));
  return roundPeso(
    _integrateHours(
      from: planStart,
      to: planEnd,
      quotedRate: quotedRate,
      history: history,
    ),
  );
}

/// Slot plus overtime at the fees in effect across the ride.
RentalCharge rentalChargeAt(
  Rental r,
  DateTime at,
  List<HourlyRateChange> history,
) {
  final base = slotCharge(
    planStart: r.approvedAt,
    plannedMinutes: r.plannedMinutes,
    quotedRate: r.ratePerHour,
    history: history,
    now: at,
    estimatedCost: r.estimatedCost,
  );
  if (r.approvedAt == null) return RentalCharge(base: base, penalty: 0);
  if (history.isEmpty) {
    final when = r.endedAt ?? at;
    return RentalCharge(
      base: base,
      penalty: penaltyForOvertimeMinutes(r, overtimeMinutesAt(r, when)),
    );
  }
  final planEnd = r.approvedAt!.add(Duration(minutes: r.plannedMinutes));
  final returned = r.endedAt ?? at;
  if (!returned.isAfter(planEnd)) return RentalCharge(base: base, penalty: 0);
  return RentalCharge(
    base: base,
    penalty: roundPeso(
      _integrateHours(
        from: planEnd,
        to: returned,
        quotedRate: r.ratePerHour,
        history: history,
        multiplier: 1.5,
      ),
    ),
  );
}

/// Amount a completed ride contributes to reports.
///
/// [Rental.actualCost] is the total staff recorded (slot plus penalty).
/// A later hourly-fee change does not replace that saved total.
double collectedAmount(Rental r) {
  if (r.actualCost != null) return r.actualCost!;
  return (r.estimatedCost ?? 0) + (r.penaltyFee ?? 0);
}

/// Base charge for the planned slot (not including overtime penalty).
double baseRentalCost(Rental r) =>
    roundPeso((r.plannedMinutes / 60.0) * r.ratePerHour);

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
    roundPeso((overtimeMin / 60.0) * r.ratePerHour * 1.5);

double suggestedTotalAt(Rental r, DateTime at) => roundPeso(
  baseRentalCost(r) + penaltyForOvertimeMinutes(r, overtimeMinutesAt(r, at)),
);

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
