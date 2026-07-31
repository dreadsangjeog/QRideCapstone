import 'supabase_client.dart';

/// Utilization metrics from ended rentals (admin sees all via RLS when [is_admin]).
class UtilizationStats {
  UtilizationStats({
    required this.totalEndedRentals,
    required this.averageDuration,
    required this.rentalsPerDay,
  });

  final int totalEndedRentals;
  final Duration? averageDuration;
  final Map<DateTime, int> rentalsPerDay;
}

class AnalyticsRepository {
  static DateTime? _parseTs(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  /// Aggregates ended rentals in the last [days] days (by `ended_at`, UTC window).
  ///
  /// Average duration is **ride time**: `approved_at` → `ended_at` when approval exists,
  /// otherwise `started_at` → `ended_at` (legacy rows).
  Future<UtilizationStats> utilizationLastDays(int days) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: days));

    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select('started_at, ended_at, approved_at')
        .eq('status', 'ended')
        .gte('ended_at', from.toIso8601String())
        .lte('ended_at', now.toIso8601String())
        .order('ended_at');

    final list = rows as List<dynamic>;
    final perDay = <DateTime, int>{};
    var totalDuration = Duration.zero;
    var countWithDuration = 0;
    var includedCount = 0;

    for (final raw in list) {
      final m = raw as Map<String, dynamic>;
      final endedAt = _parseTs(m['ended_at']);
      final startedAt = _parseTs(m['started_at']);
      final approvedAt = _parseTs(m['approved_at']);
      if (endedAt == null) continue;

      final endUtc = endedAt.toUtc();
      if (endUtc.isBefore(from) || endUtc.isAfter(now)) continue;

      includedCount++;
      final day = DateTime.utc(endUtc.year, endUtc.month, endUtc.day);
      perDay[day] = (perDay[day] ?? 0) + 1;

      final startRide = approvedAt ?? startedAt;
      if (startRide == null) continue;
      final d = endedAt.difference(startRide);
      if (d.isNegative) continue;
      totalDuration += d;
      countWithDuration++;
    }

    return UtilizationStats(
      totalEndedRentals: includedCount,
      averageDuration: countWithDuration == 0
          ? null
          : totalDuration ~/ countWithDuration,
      rentalsPerDay: perDay,
    );
  }

  /// CSV of ended rentals in the selected window (RFC-style escaping).
  Future<String> buildEndedRentalsExportCsv(int days) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: days));

    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select(
          'id, bike_id, user_id, started_at, ended_at, approved_at, '
          'planned_minutes, rate_per_hour, actual_cost, estimated_cost, penalty_fee',
        )
        .eq('status', 'ended')
        .gte('ended_at', from.toIso8601String())
        .lte('ended_at', now.toIso8601String())
        .order('ended_at');

    final list = rows as List<dynamic>;
    final header = [
      'id',
      'bike_id',
      'user_id',
      'started_at',
      'ended_at',
      'approved_at',
      'ride_duration_minutes',
      'planned_minutes',
      'rate_per_hour',
      'actual_cost',
      'estimated_cost',
      'penalty_fee',
    ];
    final lines = <String>[header.map(_csvCell).join(',')];

    for (final raw in list) {
      final m = raw as Map<String, dynamic>;
      final endedAt = _parseTs(m['ended_at']);
      if (endedAt == null) continue;
      final endUtc = endedAt.toUtc();
      if (endUtc.isBefore(from) || endUtc.isAfter(now)) continue;

      final startedAt = _parseTs(m['started_at']);
      final approvedAt = _parseTs(m['approved_at']);
      final startRide = approvedAt ?? startedAt;
      String rideMinStr = '';
      if (startRide != null) {
        final d = endedAt.difference(startRide);
        if (!d.isNegative) {
          rideMinStr = (d.inSeconds / 60.0).toStringAsFixed(2);
        }
      }

      lines.add([
        _csvCell(m['id']?.toString() ?? ''),
        _csvCell(m['bike_id']?.toString() ?? ''),
        _csvCell(m['user_id']?.toString() ?? ''),
        _csvCell(m['started_at']?.toString() ?? ''),
        _csvCell(m['ended_at']?.toString() ?? ''),
        _csvCell(m['approved_at']?.toString() ?? ''),
        _csvCell(rideMinStr),
        _csvCell(m['planned_minutes']?.toString() ?? ''),
        _csvCell(m['rate_per_hour']?.toString() ?? ''),
        _csvCell(m['actual_cost']?.toString() ?? ''),
        _csvCell(m['estimated_cost']?.toString() ?? ''),
        _csvCell(m['penalty_fee']?.toString() ?? ''),
      ].join(','));
    }

    return lines.join('\r\n');
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
