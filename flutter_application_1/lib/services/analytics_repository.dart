import 'package:excel/excel.dart';

import '../models/rental.dart';
import '../models/rental_with_bike.dart';
import '../utils/rental_billing.dart';
import 'supabase_client.dart';

class ReportDayPoint {
  const ReportDayPoint({
    required this.day,
    required this.completed,
    required this.collected,
    required this.rideMinutes,
  });

  final DateTime day;
  final int completed;
  final double collected;
  final double rideMinutes;
}

class ReportBikeStat {
  const ReportBikeStat({
    required this.name,
    required this.rides,
    required this.collected,
    required this.rideMinutes,
  });

  final String name;
  final int rides;
  final double collected;
  final double rideMinutes;
}

class ReportSnapshot {
  const ReportSnapshot({
    required this.days,
    required this.rangeStart,
    required this.rangeEndExclusive,
    required this.completedCount,
    required this.openPending,
    required this.openActive,
    required this.averageDuration,
    required this.totalRideMinutes,
    required this.ridesWithDuration,
    required this.collected,
    required this.penalties,
    required this.daily,
    required this.byWeekday,
    required this.durationBuckets,
    required this.topBikes,
    required this.rows,
  });

  final int days;
  final DateTime rangeStart;
  final DateTime rangeEndExclusive;
  final int completedCount;
  final int openPending;
  final int openActive;
  final Duration? averageDuration;
  final double totalRideMinutes;
  final int ridesWithDuration;
  final double collected;
  final double penalties;
  final List<ReportDayPoint> daily;
  final List<int> byWeekday;
  final Map<String, int> durationBuckets;
  final List<ReportBikeStat> topBikes;

  /// Completed rentals in the window, oldest return first (what the Excel lists).
  final List<RentalWithBike> rows;

  double get avgPerDay => days == 0 ? 0 : completedCount / days;

  DateTime get rangeEndInclusive =>
      rangeEndExclusive.subtract(const Duration(milliseconds: 1));
}

class AnalyticsRepository {
  static const durationBucketLabels = [
    'Under 15m',
    '15–30m',
    '30–60m',
    'Over 1h',
  ];

  static DateTime _startOfLocalDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  static DateTime _asLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt;

  /// Local calendar window: today and the previous [days] - 1 days.
  static ({DateTime start, DateTime endExclusive}) localWindow(int days) {
    final today = _startOfLocalDay(DateTime.now());
    final start = today.subtract(Duration(days: days - 1));
    final endExclusive = today.add(const Duration(days: 1));
    return (start: start, endExclusive: endExclusive);
  }

  static bool _inRange(DateTime? value, DateTime start, DateTime endExclusive) {
    if (value == null) return false;
    final local = _asLocal(value);
    return !local.isBefore(start) && local.isBefore(endExclusive);
  }

  static double? rideMinutesOf(Rental r) {
    final ended = r.endedAt;
    if (ended == null || r.status != 'ended' || r.approvedAt == null) {
      return null;
    }
    final minutes = rideElapsedMinutes(r, ended);
    if (minutes.isNaN || minutes.isInfinite || minutes < 0) return null;
    return minutes;
  }

  static double collectedOf(Rental r) {
    final base = r.actualCost ?? r.estimatedCost ?? 0;
    return base + (r.penaltyFee ?? 0);
  }

  static String _bucketFor(double minutes) {
    if (minutes < 15) return durationBucketLabels[0];
    if (minutes < 30) return durationBucketLabels[1];
    if (minutes < 60) return durationBucketLabels[2];
    return durationBucketLabels[3];
  }

  Future<ReportSnapshot> loadReport(int days) async {
    final window = localWindow(days);
    final start = window.start;
    final endExclusive = window.endExclusive;
    final fromIso = start.toUtc().toIso8601String();

    final raw = await SupabaseClientProvider.client
        .from('rentals')
        .select(
          'id, bike_id, user_id, status, started_at, ended_at, approved_at, '
          'planned_minutes, rate_per_hour, actual_cost, estimated_cost, penalty_fee, '
          'bikes(code, label), profiles(username)',
        )
        .or('ended_at.gte."$fromIso",status.eq.pending,status.eq.active')
        .order('ended_at', nullsFirst: false);

    final dailyDays = <DateTime>[
      for (var i = 0; i < days; i++) start.add(Duration(days: i)),
    ];
    final completedByDay = {for (final d in dailyDays) d: 0};
    final collectedByDay = {for (final d in dailyDays) d: 0.0};
    final minutesByDay = {for (final d in dailyDays) d: 0.0};
    final byWeekday = List<int>.filled(7, 0);
    final durationBuckets = {for (final l in durationBucketLabels) l: 0};
    final bikes = <String, ({String name, int rides, double collected, double minutes})>{};

    final seen = <String>{};
    final rows = <RentalWithBike>[];
    var openPending = 0;
    var openActive = 0;
    var totalRideMinutes = 0.0;
    var ridesWithDuration = 0;
    var collected = 0.0;
    var penalties = 0.0;

    for (final item in raw as List<dynamic>) {
      if (item is! Map<String, dynamic>) continue;
      final row = RentalWithBike.fromJoinedJson(item);
      final r = row.rental;
      if (!seen.add(r.id)) continue;

      if (r.isPending) openPending++;
      if (r.isActive) openActive++;
      if (!r.isEnded || !_inRange(r.endedAt, start, endExclusive)) continue;

      rows.add(row);
      final amount = collectedOf(r);
      collected += amount;
      penalties += r.penaltyFee ?? 0;

      final endLocal = _asLocal(r.endedAt!);
      final day = _startOfLocalDay(endLocal);
      completedByDay[day] = (completedByDay[day] ?? 0) + 1;
      collectedByDay[day] = (collectedByDay[day] ?? 0) + amount;
      byWeekday[endLocal.weekday - 1] += 1;

      final minutes = rideMinutesOf(r);
      if (minutes != null) {
        totalRideMinutes += minutes;
        ridesWithDuration++;
        minutesByDay[day] = (minutesByDay[day] ?? 0) + minutes;
        final bucket = _bucketFor(minutes);
        durationBuckets[bucket] = durationBuckets[bucket]! + 1;
      }

      final prev = bikes[r.bikeId];
      bikes[r.bikeId] = (
        name: row.bikeDisplay,
        rides: (prev?.rides ?? 0) + 1,
        collected: (prev?.collected ?? 0) + amount,
        minutes: (prev?.minutes ?? 0) + (minutes ?? 0),
      );
    }

    final topBikes = bikes.values
        .map(
          (b) => ReportBikeStat(
            name: b.name,
            rides: b.rides,
            collected: b.collected,
            rideMinutes: b.minutes,
          ),
        )
        .toList()
      ..sort((a, b) {
        final byRides = b.rides.compareTo(a.rides);
        return byRides != 0 ? byRides : b.collected.compareTo(a.collected);
      });

    return ReportSnapshot(
      days: days,
      rangeStart: start,
      rangeEndExclusive: endExclusive,
      completedCount: rows.length,
      openPending: openPending,
      openActive: openActive,
      averageDuration: ridesWithDuration == 0
          ? null
          : Duration(
              milliseconds:
                  ((totalRideMinutes / ridesWithDuration) * 60000).round(),
            ),
      totalRideMinutes: totalRideMinutes,
      ridesWithDuration: ridesWithDuration,
      collected: collected,
      penalties: penalties,
      daily: [
        for (final d in dailyDays)
          ReportDayPoint(
            day: d,
            completed: completedByDay[d] ?? 0,
            collected: collectedByDay[d] ?? 0,
            rideMinutes: minutesByDay[d] ?? 0,
          ),
      ],
      byWeekday: byWeekday,
      durationBuckets: durationBuckets,
      topBikes: topBikes,
      rows: rows,
    );
  }

  /// Excel workbook that matches [snapshot] totals: Summary, Daily, Rides.
  List<int> buildReportXlsx(ReportSnapshot snapshot) {
    final book = Excel.createExcel();
    book.rename('Sheet1', 'Summary');
    final summary = book['Summary'];
    final daily = book['Daily'];
    final rides = book['Rides'];

    void write(Sheet sheet, int row, List<CellValue> cells) {
      for (var i = 0; i < cells.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row))
            .value = cells[i];
      }
    }

    final avgMin = snapshot.ridesWithDuration == 0
        ? null
        : snapshot.totalRideMinutes / snapshot.ridesWithDuration;

    write(summary, 0, [TextCellValue('Metric'), TextCellValue('Value')]);
    final summaryRows = <List<CellValue>>[
      [TextCellValue('Period start (local)'), TextCellValue(_fmtLocal(snapshot.rangeStart))],
      [TextCellValue('Period end (local)'), TextCellValue(_fmtLocal(snapshot.rangeEndInclusive))],
      [TextCellValue('Window days'), IntCellValue(snapshot.days)],
      [TextCellValue('Completed rides'), IntCellValue(snapshot.completedCount)],
      [
        TextCellValue('Avg ride minutes'),
        if (avgMin == null) TextCellValue('') else DoubleCellValue(avgMin),
      ],
      [TextCellValue('Total ride minutes'), DoubleCellValue(snapshot.totalRideMinutes)],
      [TextCellValue('Collected (₱)'), DoubleCellValue(snapshot.collected)],
      [TextCellValue('Penalties included (₱)'), DoubleCellValue(snapshot.penalties)],
      [TextCellValue('Open pending now'), IntCellValue(snapshot.openPending)],
      [TextCellValue('Open active now'), IntCellValue(snapshot.openActive)],
    ];
    for (var i = 0; i < summaryRows.length; i++) {
      write(summary, i + 1, summaryRows[i]);
    }

    write(daily, 0, [
      TextCellValue('Date'),
      TextCellValue('Completed rides'),
      TextCellValue('Ride minutes'),
      TextCellValue('Collected (₱)'),
    ]);
    for (var i = 0; i < snapshot.daily.length; i++) {
      final d = snapshot.daily[i];
      write(daily, i + 1, [
        TextCellValue(_fmtDate(d.day)),
        IntCellValue(d.completed),
        DoubleCellValue(d.rideMinutes),
        DoubleCellValue(d.collected),
      ]);
    }

    write(rides, 0, [
      TextCellValue('Rental ID'),
      TextCellValue('Bike code'),
      TextCellValue('Bike label'),
      TextCellValue('Rider'),
      TextCellValue('Requested at (local)'),
      TextCellValue('Approved at (local)'),
      TextCellValue('Ended at (local)'),
      TextCellValue('Ride minutes'),
      TextCellValue('Planned minutes'),
      TextCellValue('Rate per hour (₱)'),
      TextCellValue('Actual cost (₱)'),
      TextCellValue('Estimated cost (₱)'),
      TextCellValue('Penalty fee (₱)'),
      TextCellValue('Collected (₱)'),
    ]);
    for (var i = 0; i < snapshot.rows.length; i++) {
      final row = snapshot.rows[i];
      final r = row.rental;
      final minutes = rideMinutesOf(r);
      write(rides, i + 1, [
        TextCellValue(r.id),
        TextCellValue(row.bike?.code ?? ''),
        TextCellValue(row.bike?.label ?? ''),
        TextCellValue(row.riderDisplay),
        TextCellValue(_fmtLocal(r.startedAt)),
        TextCellValue(_fmtLocal(r.approvedAt)),
        TextCellValue(_fmtLocal(r.endedAt)),
        if (minutes == null) TextCellValue('') else DoubleCellValue(minutes),
        IntCellValue(r.plannedMinutes),
        DoubleCellValue(r.ratePerHour),
        if (r.actualCost == null) TextCellValue('') else DoubleCellValue(r.actualCost!),
        if (r.estimatedCost == null)
          TextCellValue('')
        else
          DoubleCellValue(r.estimatedCost!),
        if (r.penaltyFee == null) TextCellValue('') else DoubleCellValue(r.penaltyFee!),
        DoubleCellValue(collectedOf(r)),
      ]);
    }

    return book.encode()!;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _fmtDate(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _fmtLocal(DateTime? dt) {
    if (dt == null) return '';
    final l = _asLocal(dt);
    return '${_fmtDate(l)} ${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
  }

}
