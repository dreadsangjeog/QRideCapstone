import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/analytics_repository.dart';
import '../../theme/brand.dart';
import '../../utils/rental_billing.dart';
import '../../utils/save_bytes_file.dart';
import '../../widgets/qride_glass.dart';
import 'admin_report_charts.dart';

final _peso = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
final _pesoExact = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

const _green = Color(0xFF22C55E);
const _violet = Color(0xFF7C3AED);
const _cyan = Color(0xFF0891B2);
const _pink = Color(0xFFDB2777);
const _orange = Color(0xFFEA580C);

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key, required this.repo});

  final AnalyticsRepository repo;

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  int _days = 7;
  late Future<ReportSnapshot> _future = _load();
  bool _exporting = false;

  Future<ReportSnapshot> _load() => widget.repo.loadReport(_days);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _exportExcel(ReportSnapshot snapshot) async {
    setState(() => _exporting = true);
    try {
      final bytes = widget.repo.buildReportXlsx(snapshot);
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      final filename = 'qride-report-${_days}d-$stamp.xlsx';
      await saveBytesFile(
        filename: filename,
        bytes: bytes,
        mime:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        subject: 'QRide report last $_days days',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${snapshot.completedCount} completed rides · '
            '${_pesoExact.format(snapshot.collected)} collected',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
        onRefresh: _refresh,
        color: QrideBrand.accent,
        child: FutureBuilder<ReportSnapshot>(
          key: ValueKey<int>(_days),
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load reports',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ),
                ],
              );
            }
            return _ReportsBody(
              stats: snapshot.data!,
              days: _days,
              exporting: _exporting,
              onDays: (days) {
                setState(() {
                  _days = days;
                  _future = _load();
                });
              },
              onExport: () => _exportExcel(snapshot.data!),
            );
          },
        ),
    );
  }
}

class _ReportsBody extends StatelessWidget {
  const _ReportsBody({
    required this.stats,
    required this.days,
    required this.exporting,
    required this.onDays,
    required this.onExport,
  });

  final ReportSnapshot stats;
  final int days;
  final bool exporting;
  final ValueChanged<int> onDays;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 980;
    final mid = width >= 760;
    final range = DateFormat('MMM d');
    final avg = stats.averageDuration;

    final kpis = [
      _SoftKpi(
        label: 'Completed',
        value: '${stats.completedCount}',
        sub: '${stats.avgPerDay.toStringAsFixed(1)} rides per day',
        color: _violet,
        wash: const Color(0xFFEEE7FF),
      ),
      _SoftKpi(
        label: 'Avg ride time',
        value: avg == null
            ? '—'
            : formatRideDurationMinutes(avg.inSeconds / 60.0),
        sub: 'From approval to return',
        color: _cyan,
        wash: const Color(0xFFD9F4FB),
      ),
      _SoftKpi(
        label: 'Total ride time',
        value: stats.totalRideMinutes <= 0
            ? '—'
            : formatRideDurationMinutes(stats.totalRideMinutes),
        sub: 'Across ${stats.ridesWithDuration} timed rides',
        color: QrideBrand.accent,
        wash: const Color(0xFFDCEBFF),
      ),
      _SoftKpi(
        label: 'Collected',
        value: _peso.format(stats.collected),
        sub: stats.penalties > 0
            ? 'Incl. ${_peso.format(stats.penalties)} penalties'
            : 'No penalties charged',
        color: _pink,
        wash: const Color(0xFFFFE4F0),
      ),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 28 : 18, 22, wide ? 28 : 18, 36),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reports',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${range.format(stats.rangeStart)} – ${range.format(stats.rangeEndInclusive)}  ·  completed rides, local time',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: exporting ? null : onExport,
              icon: exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(exporting ? 'Preparing…' : 'Export Excel'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in const [7, 14, 30])
              ChoiceChip(
                label: Text('$d days'),
                selected: days == d,
                showCheckmark: false,
                selectedColor: QrideBrand.accent,
                labelStyle: TextStyle(
                  color: days == d ? Colors.white : cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => onDays(d),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (wide)
          Row(
            children: [
              for (var i = 0; i < kpis.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: kpis[i]),
              ],
            ],
          )
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.28,
            children: kpis,
          ),
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _CompletedTrendCard(stats: stats)),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _RevenueCard(stats: stats)),
            ],
          )
        else ...[
          _CompletedTrendCard(stats: stats),
          const SizedBox(height: 14),
          _RevenueCard(stats: stats),
        ],
        const SizedBox(height: 14),
        if (mid)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TopBikesCard(stats: stats)),
              const SizedBox(width: 14),
              Expanded(child: _DurationDonutCard(stats: stats)),
              const SizedBox(width: 14),
              Expanded(child: _WeekdayCard(stats: stats)),
            ],
          )
        else ...[
          _TopBikesCard(stats: stats),
          const SizedBox(height: 14),
          _DurationDonutCard(stats: stats),
          const SizedBox(height: 14),
          _WeekdayCard(stats: stats),
        ],
      ],
    );
  }
}

List<({String label, String value, Color color})> _dayDetails(
  ReportDayPoint d,
) =>
    [
      (label: 'Rides', value: '${d.completed}', color: _green),
      (label: 'Collected', value: _pesoExact.format(d.collected), color: _pink),
      (
        label: 'Ride time',
        value: d.rideMinutes <= 0 ? '—' : formatRideDurationMinutes(d.rideMinutes),
        color: QrideBrand.accent,
      ),
    ];

String _dayTitle(ReportDayPoint d) => DateFormat('EEEE, MMM d').format(d.day);

class _SoftKpi extends StatelessWidget {
  const _SoftKpi({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.wash,
  });

  final String label;
  final String value;
  final String sub;
  final Color color;
  final Color wash;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassPanel(
      tint: dark ? color.withValues(alpha: 0.18) : wash.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.86),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 30,
                height: 1,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CompletedTrendCard extends StatelessWidget {
  const _CompletedTrendCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final d in stats.daily)
        stats.days > 14
            ? DateFormat('d').format(d.day)
            : DateFormat('EEE d').format(d.day),
    ];
    return _ChartCard(
      title: 'Completed rides',
      subtitle: 'Hover or tap the line for daily details',
      child: ReportLineChart(
        height: 230,
        labels: labels,
        series: [
          ReportLineSeries(
            label: 'Rides',
            color: _green,
            values: [for (final d in stats.daily) d.completed.toDouble()],
          ),
        ],
        tooltipTitle: (i) => _dayTitle(stats.daily[i]),
        tooltipLines: (i) => _dayDetails(stats.daily[i]),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title: 'Revenue',
      subtitle: '${_pesoExact.format(stats.collected)} in this window',
      child: Column(
        children: [
          ReportLineChart(
            height: 150,
            labels: [
              for (final d in stats.daily) DateFormat('d').format(d.day),
            ],
            yLabel: (v) => v >= 1000
                ? '₱${(v / 1000).toStringAsFixed(1)}k'
                : '₱${v.round()}',
            series: [
              ReportLineSeries(
                label: 'Collected',
                color: _pink,
                values: [for (final d in stats.daily) d.collected],
              ),
            ],
            tooltipTitle: (i) => _dayTitle(stats.daily[i]),
            tooltipLines: (i) => _dayDetails(stats.daily[i]),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Pending now',
                  value: '${stats.openPending}',
                  color: _orange,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Riding now',
                  value: '${stats.openActive}',
                  color: QrideBrand.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBikesCard extends StatelessWidget {
  const _TopBikesCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = stats.topBikes.take(5).toList();
    final maxRides = top.isEmpty ? 1 : top.first.rides;
    const palette = [QrideBrand.accent, _violet, _cyan, _pink, _orange];

    return _ChartCard(
      title: 'Top bikes',
      subtitle: 'Most completed rides',
      child: top.isEmpty
          ? SizedBox(
              height: 148,
              child: Center(
                child: Text(
                  'No completed rides yet.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == top.length - 1 ? 0 : 12),
                    child: Tooltip(
                      message: '${top[i].rides} rides · '
                          '${_pesoExact.format(top[i].collected)} · '
                          '${formatRideDurationMinutes(top[i].rideMinutes)} ridden',
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: palette[i].withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: palette[i],
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        top[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${top[i].rides}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: palette[i],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    minHeight: 6,
                                    value: top[i].rides / maxRides,
                                    color: palette[i],
                                    backgroundColor:
                                        palette[i].withValues(alpha: 0.10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DurationDonutCard extends StatelessWidget {
  const _DurationDonutCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFF38BDF8), QrideBrand.accent, _violet, _pink];
    return _ChartCard(
      title: 'Ride length',
      subtitle: 'How long riders keep bikes',
      child: ReportDonutChart(
        centerValue: '${stats.ridesWithDuration}',
        centerLabel: 'timed',
        slices: [
          for (var i = 0; i < AnalyticsRepository.durationBucketLabels.length; i++)
            (
              label: AnalyticsRepository.durationBucketLabels[i],
              value: stats.durationBuckets[
                      AnalyticsRepository.durationBucketLabels[i]] ??
                  0,
              color: colors[i],
            ),
        ],
      ),
    );
  }
}

class _WeekdayCard extends StatelessWidget {
  const _WeekdayCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title: 'Completed by weekday',
      subtitle: 'Busiest days of the week',
      child: ReportBarChart(
        height: 160,
        labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        values: [for (final n in stats.byWeekday) n.toDouble()],
        color: QrideBrand.accent,
      ),
    );
  }
}
