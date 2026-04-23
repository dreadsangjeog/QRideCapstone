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
  /// Aggregates ended rentals in the last [days] days (by `ended_at`).
  Future<UtilizationStats> utilizationLastDays(int days) async {
    final now = DateTime.now().toUtc();
    final from = now.subtract(Duration(days: days));

    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select('started_at, ended_at')
        .eq('status', 'ended')
        .gte('ended_at', from.toIso8601String())
        .order('ended_at');

    final list = rows as List<dynamic>;
    final perDay = <DateTime, int>{};
    var totalDuration = Duration.zero;
    var countWithDuration = 0;

    for (final raw in list) {
      final m = raw as Map<String, dynamic>;
      final endedAt = m['ended_at'] == null
          ? null
          : DateTime.tryParse(m['ended_at'].toString());
      final startedAt = m['started_at'] == null
          ? null
          : DateTime.tryParse(m['started_at'].toString());
      if (endedAt == null || startedAt == null) continue;

      final day = DateTime.utc(endedAt.year, endedAt.month, endedAt.day);
      perDay[day] = (perDay[day] ?? 0) + 1;

      final d = endedAt.difference(startedAt);
      if (d.isNegative) continue;
      totalDuration += d;
      countWithDuration++;
    }

    return UtilizationStats(
      totalEndedRentals: list.length,
      averageDuration: countWithDuration == 0
          ? null
          : totalDuration ~/ countWithDuration,
      rentalsPerDay: perDay,
    );
  }
}
