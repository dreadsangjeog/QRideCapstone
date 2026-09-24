import '../models/rental.dart';
import '../models/rental_with_bike.dart';
import '../utils/rental_billing.dart';
import 'supabase_client.dart';

class ReportDayPoint {
  const ReportDayPoint({
    required this.day,
    required this.requests,
    required this.completed,
  });

  final DateTime day;
  final int requests;
  final int completed;
}

class ReportSnapshot {
  const ReportSnapshot({
    required this.days,
    required this.rangeStart,
    required this.rangeEndExclusive,
    required this.completedCount,
    required this.requestCount,
    required this.openPending,
    required this.openActive,
    required this.averageDuration,
    required this.totalRideMinutes,
    required this.ridesWithDuration,
    required this.collected,
    required this.daily,
    required this.byWeekday,
    required this.statusMix,
    required this.durationBuckets,
    required this.rows,
  });

  final int days;
  final DateTime rangeStart;
  final DateTime rangeEndExclusive;
  final int completedCount;
  final int requestCount;
  final int openPending;
  final int openActive;
  final Duration? averageDuration;
  final double totalRideMinutes;
  final int ridesWithDuration;
  final double collected;
  final List<ReportDayPoint> daily;
  final List<int> byWeekday;
  final Map<String, int> statusMix;
  final Map<String, int> durationBuckets;
  final List<RentalWithBike> rows;

  double get avgPerDay => days == 0 ? 0 : completedCount / days;

  DateTime get rangeEndInclusive =>
      rangeEndExclusive.subtract(const Duration(milliseconds: 1));
}

class AnalyticsRepository {
  static DateTime _startOfLocalDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  static DateTime _asLocal(DateTime dt) =>
      dt.isUtc ? dt.toLocal() : dt;

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
    if (ended == null || r.status != 'ended') return null;
    final minutes = rideElapsedMinutes(r, ended);
    if (minutes.isNaN || minutes.isInfinite || minutes < 0) return null;
    return minutes;
  }

  static double collectedOf(Rental r) {
    final base = r.actualCost ?? r.estimatedCost ?? 0;
    return base + (r.penaltyFee ?? 0);
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
        .or(
          'started_at.gte."$fromIso",ended_at.gte."$fromIso",'
          'status.eq.pending,status.eq.active',
        )
        .order('started_at');

    final seen = <String>{};
    final rows = <RentalWithBike>[];
    for (final item in raw as List<dynamic>) {
      if (item is! Map<String, dynamic>) continue;
      final row = RentalWithBike.fromJoinedJson(item);
      if (!seen.add(row.rental.id)) continue;
      final r = row.rental;
      final startedIn = _inRange(r.startedAt, start, endExclusive);
      final endedIn = _inRange(r.endedAt, start, endExclusive);
      final openNow = r.isPending || r.isActive;
      if (startedIn || endedIn || openNow) {
        rows.add(row);
      }
    }

    final dailyDays = <DateTime>[
      for (var i = 0; i < days; i++) start.add(Duration(days: i)),
    ];
    final requestsByDay = {for (final d in dailyDays) d: 0};
    final completedByDay = {for (final d in dailyDays) d: 0};
    final byWeekday = List<int>.filled(7, 0);
    final statusMix = <String, int>{
      'pending': 0,
      'active': 0,
      'ended': 0,
    };
    final durationBuckets = <String, int>{
      'Under 15m': 0,
      '15–30m': 0,
      '30–60m': 0,
      'Over 1h': 0,
    };

    var completedCount = 0;
    var requestCount = 0;
    var openPending = 0;
    var openActive = 0;
    var totalRideMinutes = 0.0;
    var ridesWithDuration = 0;
    var collected = 0.0;

    for (final row in rows) {
      final r = row.rental;
      if (r.isPending) openPending++;
      if (r.isActive) openActive++;

      if (_inRange(r.startedAt, start, endExclusive)) {
        requestCount++;
        final day = _startOfLocalDay(_asLocal(r.startedAt));
        if (requestsByDay.containsKey(day)) {
          requestsByDay[day] = (requestsByDay[day] ?? 0) + 1;
        }
        if (statusMix.containsKey(r.status)) {
          statusMix[r.status] = (statusMix[r.status] ?? 0) + 1;
        }
      }

      if (r.isEnded && _inRange(r.endedAt, start, endExclusive)) {
        completedCount++;
        collected += collectedOf(r);
        final endLocal = _asLocal(r.endedAt!);
        final day = _startOfLocalDay(endLocal);
        if (completedByDay.containsKey(day)) {
          completedByDay[day] = (completedByDay[day] ?? 0) + 1;
        }
        byWeekday[endLocal.weekday - 1] += 1;
        final minutes = rideMinutesOf(r);
        if (minutes != null) {
          totalRideMinutes += minutes;
          ridesWithDuration++;
          if (minutes < 15) {
            durationBuckets['Under 15m'] = durationBuckets['Under 15m']! + 1;
          } else if (minutes < 30) {
            durationBuckets['15–30m'] = durationBuckets['15–30m']! + 1;
          } else if (minutes < 60) {
            durationBuckets['30–60m'] = durationBuckets['30–60m']! + 1;
          } else {
            durationBuckets['Over 1h'] = durationBuckets['Over 1h']! + 1;
          }
        }
      }
    }

    return ReportSnapshot(
      days: days,
      rangeStart: start,
      rangeEndExclusive: endExclusive,
      completedCount: completedCount,
      requestCount: requestCount,
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
      daily: [
        for (final d in dailyDays)
          ReportDayPoint(
            day: d,
            requests: requestsByDay[d] ?? 0,
            completed: completedByDay[d] ?? 0,
          ),
      ],
      byWeekday: byWeekday,
      statusMix: statusMix,
      durationBuckets: durationBuckets,
      rows: rows,
    );
  }

  /// CSV that matches [snapshot] totals: summary block + one row per rental.
  String buildReportCsv(ReportSnapshot snapshot) {
    String money(num n) => n.toStringAsFixed(2);
    final avgMin = snapshot.ridesWithDuration == 0
        ? ''
        : (snapshot.totalRideMinutes / snapshot.ridesWithDuration)
            .toStringAsFixed(2);
    final lines = <String>[
      ['section', 'metric', 'value'].map(_csvCell).join(','),
      ['summary', 'period_start_local', snapshot.rangeStart.toIso8601String()]
          .map(_csvCell)
          .join(','),
      [
        'summary',
        'period_end_local',
        snapshot.rangeEndInclusive.toIso8601String(),
      ].map(_csvCell).join(','),
      ['summary', 'window_days', '${snapshot.days}'].map(_csvCell).join(','),
      ['summary', 'requests', '${snapshot.requestCount}'].map(_csvCell).join(','),
      ['summary', 'completed', '${snapshot.completedCount}']
          .map(_csvCell)
          .join(','),
      ['summary', 'open_pending', '${snapshot.openPending}']
          .map(_csvCell)
          .join(','),
      ['summary', 'open_active', '${snapshot.openActive}']
          .map(_csvCell)
          .join(','),
      ['summary', 'avg_ride_minutes', avgMin].map(_csvCell).join(','),
      ['summary', 'collected', money(snapshot.collected)].map(_csvCell).join(','),
      ['summary', 'export_rows', '${snapshot.rows.length}']
          .map(_csvCell)
          .join(','),
      '',
      [
        'rental_id',
        'status',
        'bike_code',
        'bike_label',
        'rider',
        'requested_at_local',
        'approved_at_local',
        'ended_at_local',
        'ride_minutes',
        'planned_minutes',
        'rate_per_hour',
        'actual_cost',
        'estimated_cost',
        'penalty_fee',
        'collected',
        'in_request_total',
        'in_completed_total',
      ].map(_csvCell).join(','),
    ];

    for (final row in snapshot.rows) {
      final r = row.rental;
      final minutes = rideMinutesOf(r);
      final requestedIn = _inRange(
        r.startedAt,
        snapshot.rangeStart,
        snapshot.rangeEndExclusive,
      );
      final completedIn =
          r.isEnded &&
          _inRange(r.endedAt, snapshot.rangeStart, snapshot.rangeEndExclusive);
      lines.add(
        [
          r.id,
          r.status,
          row.bike?.code ?? '',
          row.bike?.label ?? '',
          row.riderDisplay,
          _fmtLocal(r.startedAt),
          _fmtLocal(r.approvedAt),
          _fmtLocal(r.endedAt),
          minutes == null ? '' : minutes.toStringAsFixed(2),
          '${r.plannedMinutes}',
          money(r.ratePerHour),
          r.actualCost == null ? '' : money(r.actualCost!),
          r.estimatedCost == null ? '' : money(r.estimatedCost!),
          r.penaltyFee == null ? '' : money(r.penaltyFee!),
          money(collectedOf(r)),
          requestedIn ? '1' : '0',
          completedIn ? '1' : '0',
        ].map(_csvCell).join(','),
      );
    }

    return lines.join('\r\n');
  }

  static String _fmtLocal(DateTime? dt) {
    if (dt == null) return '';
    return _asLocal(dt).toIso8601String();
  }

  static String _csvCell(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
}
