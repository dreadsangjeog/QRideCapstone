import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/analytics_repository.dart';
import '../../theme/brand.dart';
import '../../utils/rental_billing.dart';
import '../../utils/save_text_file.dart';
import 'admin_report_charts.dart';

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

  Future<void> _exportCsv(ReportSnapshot snapshot) async {
    setState(() => _exporting = true);
    try {
      final csv = widget.repo.buildReportCsv(snapshot);
      final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
      final filename = 'qride-report-${_days}d-$stamp.csv';
      await saveTextFile(
        filename: filename,
        contents: csv,
        mime: 'text/csv',
        subject: 'QRide report last $_days days',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${snapshot.rows.length} rentals · '
            '${snapshot.completedCount} completed · '
            '${snapshot.requestCount} requests',
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
    return ColoredBox(
      color: cs.brightness == Brightness.dark
          ? QrideBrand.night
          : const Color(0xFFF3F6FB),
      child: RefreshIndicator(
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
              onExport: () => _exportCsv(snapshot.data!),
            );
          },
        ),
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
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final mid = MediaQuery.sizeOf(context).width >= 760;
    final range = DateFormat('MMM d');
    final avg = stats.averageDuration;
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 0);

    final kpis = [
      _SoftKpi(
        label: 'Completed',
        value: '${stats.completedCount}',
        sub: 'Ended rides in range',
        color: const Color(0xFF7C3AED),
        wash: const Color(0xFFEEE7FF),
      ),
      _SoftKpi(
        label: 'Avg ride time',
        value: avg == null
            ? '—'
            : formatRideDurationMinutes(avg.inSeconds / 60.0),
        sub: stats.ridesWithDuration == 0
            ? 'No timed rides yet'
            : 'From approval to return',
        color: const Color(0xFF0891B2),
        wash: const Color(0xFFD9F4FB),
      ),
      _SoftKpi(
        label: 'Requests',
        value: '${stats.requestCount}',
        sub: 'Submitted in this window',
        color: QrideBrand.accent,
        wash: const Color(0xFFDCEBFF),
      ),
      _SoftKpi(
        label: 'Collected',
        value: money.format(stats.collected),
        sub: 'Actual + penalty on ended rides',
        color: const Color(0xFFDB2777),
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
                    '${range.format(stats.rangeStart)} – ${range.format(stats.rangeEndInclusive)}  ·  local time',
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
              label: Text(exporting ? 'Preparing…' : 'Export CSV'),
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
              Expanded(flex: 7, child: _RequestsCompletedCard(stats: stats)),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _OpenNowCard(stats: stats)),
            ],
          )
        else ...[
          _RequestsCompletedCard(stats: stats),
          const SizedBox(height: 14),
          _OpenNowCard(stats: stats),
        ],
        const SizedBox(height: 14),
        if (mid)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StatusDonutCard(stats: stats)),
              const SizedBox(width: 14),
              Expanded(child: _DurationDonutCard(stats: stats)),
              const SizedBox(width: 14),
              Expanded(child: _WeekdayCard(stats: stats)),
            ],
          )
        else ...[
          _StatusDonutCard(stats: stats),
          const SizedBox(height: 14),
          _DurationDonutCard(stats: stats),
          const SizedBox(height: 14),
          _WeekdayCard(stats: stats),
        ],
      ],
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: dark ? color.withValues(alpha: 0.16) : wash,
        borderRadius: BorderRadius.circular(22),
      ),
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
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 30,
              height: 1,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
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
  const _ChartCard({required this.title, required this.child, this.legend});

  final String title;
  final Widget child;
  final Widget? legend;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              ?legend,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _RequestsCompletedCard extends StatelessWidget {
  const _RequestsCompletedCard({required this.stats});
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
      title: 'Requests vs completed',
      legend: const Row(
        children: [
          _LegendDot(color: QrideBrand.accent, label: 'Requests'),
          SizedBox(width: 12),
          _LegendDot(color: Color(0xFF22C55E), label: 'Completed'),
        ],
      ),
      child: ReportLineChart(
        labels: labels,
        series: [
          ReportLineSeries(
            label: 'Requests',
            color: QrideBrand.accent,
            values: [for (final d in stats.daily) d.requests.toDouble()],
          ),
          ReportLineSeries(
            label: 'Completed',
            color: const Color(0xFF22C55E),
            values: [for (final d in stats.daily) d.completed.toDouble()],
          ),
        ],
      ),
    );
  }
}

class _OpenNowCard extends StatelessWidget {
  const _OpenNowCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title: 'Open now',
      child: Column(
        children: [
          ReportLineChart(
            height: 120,
            labels: [
              for (final d in stats.daily) DateFormat('d').format(d.day),
            ],
            series: [
              ReportLineSeries(
                label: 'Completed',
                color: const Color(0xFF7C3AED),
                values: [for (final d in stats.daily) d.completed.toDouble()],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Pending',
                  value: '${stats.openPending}',
                  color: const Color(0xFFEA580C),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Active',
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

class _StatusDonutCard extends StatelessWidget {
  const _StatusDonutCard({required this.stats});
  final ReportSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final total = stats.statusMix.values.fold<int>(0, (a, b) => a + b);
    return _ChartCard(
      title: 'Requests by status',
      child: ReportDonutChart(
        centerValue: '$total',
        centerLabel: 'in range',
        slices: [
          (
            label: 'Ended',
            value: stats.statusMix['ended'] ?? 0,
            color: const Color(0xFF22C55E),
          ),
          (
            label: 'Active',
            value: stats.statusMix['active'] ?? 0,
            color: QrideBrand.accent,
          ),
          (
            label: 'Pending',
            value: stats.statusMix['pending'] ?? 0,
            color: const Color(0xFFEA580C),
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
    return _ChartCard(
      title: 'Ride length',
      child: ReportDonutChart(
        centerValue: '${stats.ridesWithDuration}',
        centerLabel: 'timed',
        slices: [
          (
            label: 'Under 15m',
            value: stats.durationBuckets['Under 15m'] ?? 0,
            color: const Color(0xFF38BDF8),
          ),
          (
            label: '15–30m',
            value: stats.durationBuckets['15–30m'] ?? 0,
            color: QrideBrand.accent,
          ),
          (
            label: '30–60m',
            value: stats.durationBuckets['30–60m'] ?? 0,
            color: const Color(0xFF7C3AED),
          ),
          (
            label: 'Over 1h',
            value: stats.durationBuckets['Over 1h'] ?? 0,
            color: const Color(0xFFDB2777),
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
      child: ReportBarChart(
        labels: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        values: [for (final n in stats.byWeekday) n.toDouble()],
        color: QrideBrand.accent,
      ),
    );
  }
}
