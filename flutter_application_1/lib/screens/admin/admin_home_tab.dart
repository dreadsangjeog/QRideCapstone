import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/bike.dart';
import '../../models/rental_with_bike.dart';
import '../../services/admin_repository.dart';
import '../../services/analytics_repository.dart';
import '../../theme/brand.dart';
import '../../utils/rental_billing.dart';
import '../../widgets/qride_glass.dart';
import 'admin_layout.dart';
import 'admin_report_charts.dart';

final _peso = NumberFormat.currency(symbol: '₱', decimalDigits: 0);
final _pesoExact = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

const _green = Color(0xFF16A34A);
const _orange = Color(0xFFEA580C);
const _pink = Color(0xFFDB2777);

/// Overview home for admins — KPIs, fleet health, today, and live queues.
class AdminHomeTab extends StatefulWidget {
  const AdminHomeTab({
    super.key,
    required this.repo,
    required this.pendingCount,
    required this.onOpenTab,
  });

  final AdminRepository repo;
  final int pendingCount;
  final ValueChanged<int> onOpenTab;

  @override
  State<AdminHomeTab> createState() => AdminHomeTabState();
}

class AdminHomeTabState extends State<AdminHomeTab> {
  final _analytics = AnalyticsRepository();
  bool _loading = true;
  List<Bike> _bikes = const [];
  int _active = 0;
  ReportSnapshot? _week;
  List<RentalWithBike> _pending = const [];
  List<RentalWithBike> _rides = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> refresh() => _load();

  Future<void> _load() async {
    try {
      final bikesF = widget.repo.fetchBikes();
      final pendingF = widget.repo.fetchPendingRentals();
      final activeF = widget.repo.fetchActiveRentalsWithBikes();
      final weekF = _analytics.loadReport(7);
      final bikes = await bikesF;
      final pending = await pendingF;
      final active = await activeF;
      ReportSnapshot? week;
      try {
        week = await weekF;
      } catch (_) {
        week = null;
      }
      if (!mounted) return;
      setState(() {
        _bikes = [...bikes]..sort((a, b) => a.code.compareTo(b.code));
        _active = active.length;
        _week = week;
        _pending = pending.take(5).toList();
        _rides = active.take(5).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final wide = adminWide(context);
    final week = _week;

    final kpis = [
      _KpiCard(
        label: 'Pending',
        hint: widget.pendingCount > 0 ? 'Needs your approval' : 'All caught up',
        value: '${widget.pendingCount}',
        icon: Icons.inbox_rounded,
        color: _orange,
        alert: widget.pendingCount > 0,
        onTap: () => widget.onOpenTab(2),
      ),
      _KpiCard(
        label: 'Riding now',
        hint: 'Active rentals',
        value: '$_active',
        icon: Icons.near_me_rounded,
        color: QrideBrand.accent,
        onTap: () => widget.onOpenTab(3),
      ),
      _KpiCard(
        label: 'Completed · 7d',
        hint: week?.averageDuration == null
            ? 'No timed rides yet'
            : 'Avg ${formatRideDurationMinutes(week!.averageDuration!.inSeconds / 60)} per ride',
        value: '${week?.completedCount ?? 0}',
        icon: Icons.task_alt_rounded,
        color: _green,
        onTap: () => widget.onOpenTab(7),
      ),
      _KpiCard(
        label: 'Collected · 7d',
        hint: 'From completed rides',
        value: _peso.format(week?.collected ?? 0),
        icon: Icons.payments_rounded,
        color: _pink,
        onTap: () => widget.onOpenTab(7),
      ),
    ];

    final fleet = _FleetCard(
      bikes: _bikes,
      wide: wide,
      onOpenBikes: () => widget.onOpenTab(1),
    );
    final today = _TodayCard(week: week, fill: wide);

    return RefreshIndicator(
      onRefresh: _load,
      color: QrideBrand.accent,
      child: ListView(
        padding: adminPagePadding(context),
        children: [
          AdminContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminPageHeader(
                  title: 'Overview',
                  subtitle: DateFormat('EEEE, MMMM d').format(DateTime.now()),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (wide) ...[
                        _HeaderAction(
                          icon: Icons.map_rounded,
                          label: 'Live map',
                          onTap: () => widget.onOpenTab(5),
                        ),
                        _HeaderAction(
                          icon: Icons.badge_rounded,
                          label: 'Verify users',
                          onTap: () => widget.onOpenTab(6),
                        ),
                      ],
                      IconButton.filledTonal(
                        tooltip: 'Refresh',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: cs.brightness == Brightness.dark
                              ? Colors.white.withValues(alpha: 0.10)
                              : Colors.white.withValues(alpha: 0.38),
                          foregroundColor: QrideBrand.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  if (width >= 860)
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
                      childAspectRatio: 1.45,
                      children: kpis,
                    ),
                  const SizedBox(height: 16),
                  if (wide)
                    SizedBox(
                      height: 300,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 8, child: fleet),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: today),
                        ],
                      ),
                    )
                  else ...[
                    fleet,
                    const SizedBox(height: 14),
                    today,
                  ],
                  const SizedBox(height: 16),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _pendingPanel()),
                        const SizedBox(width: 16),
                        Expanded(child: _ridesPanel()),
                      ],
                    )
                  else ...[
                    _pendingPanel(),
                    const SizedBox(height: 14),
                    _ridesPanel(),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingPanel() => _QueuePanel(
        title: 'Waiting for approval',
        icon: Icons.hourglass_top_rounded,
        color: _orange,
        count: widget.pendingCount,
        empty: 'No pending rental requests.',
        emptyIcon: Icons.check_circle_outline_rounded,
        items: _pending,
        kind: 'pending',
        onSeeAll: () => widget.onOpenTab(2),
      );

  Widget _ridesPanel() => _QueuePanel(
        title: 'Rides in progress',
        icon: Icons.near_me_rounded,
        color: QrideBrand.accent,
        count: _active,
        empty: 'No active rides right now.',
        emptyIcon: Icons.directions_bike_outlined,
        items: _rides,
        kind: 'active',
        onSeeAll: () => widget.onOpenTab(3),
      );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        backgroundColor: cs.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.38),
        side: BorderSide(
          color: Colors.white.withValues(
            alpha: cs.brightness == Brightness.dark ? 0.18 : 0.7,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Fleet health ──────────────────────────────────────────────────────────────

Color _bikeStatusColor(String status, ColorScheme cs) => switch (status) {
      'available' => _green,
      'rented' => QrideBrand.accent,
      'maintenance' => cs.error,
      _ => cs.outline,
    };

String _bikeStatusLabel(String status) => switch (status) {
      'available' => 'Available',
      'rented' => 'On rent',
      'maintenance' => 'Maintenance',
      _ => status,
    };

class _FleetCard extends StatelessWidget {
  const _FleetCard({
    required this.bikes,
    required this.wide,
    required this.onOpenBikes,
  });

  final List<Bike> bikes;
  final bool wide;
  final VoidCallback onOpenBikes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = bikes.length;
    int count(String s) => bikes.where((b) => b.status == s).length;
    final available = count('available');
    final rented = count('rented');
    final maintenance = count('maintenance');
    final other = total - available - rented - maintenance;
    final segments = [
      (label: 'Available', value: available, color: _green),
      (label: 'On rent', value: rented, color: QrideBrand.accent),
      (label: 'Maintenance', value: maintenance, color: cs.error),
      if (other > 0) (label: 'Other', value: other, color: cs.outline),
    ];
    final readyPct = total == 0 ? 0 : (available / total * 100).round();

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$available',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 44,
                height: 1,
                letterSpacing: -1.4,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 5),
              child: Text(
                'of $total ready',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$readyPct% ready',
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 10,
            child: total == 0
                ? ColoredBox(color: cs.surfaceContainerHighest)
                : Row(
                    children: [
                      for (final s in segments)
                        if (s.value > 0)
                          Expanded(
                            flex: s.value,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              color: s.color,
                            ),
                          ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        for (final s in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: s.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  '${s.value}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: s.value > 0 ? s.color : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final flagged = [
      for (final b in bikes)
        if (b.status != 'available' && b.status != 'rented') b,
    ];
    final maxRows = wide ? 3 : 4;
    final shown = flagged.take(maxRows).toList();
    final hidden = flagged.length - shown.length;

    final attention = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'NEEDS ATTENTION',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        if (total == 0)
          _AttentionEmpty(
            icon: Icons.pedal_bike_outlined,
            color: cs.onSurfaceVariant,
            title: 'No bikes yet',
            subtitle: 'Add bikes to start tracking fleet health.',
          )
        else if (flagged.isEmpty)
          const _AttentionEmpty(
            icon: Icons.verified_rounded,
            color: _green,
            title: 'All bikes in service',
            subtitle: 'Nothing is flagged for maintenance.',
          )
        else ...[
          for (final b in shown)
            _AttentionRow(bike: b, onTap: onOpenBikes),
          if (hidden > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenBikes,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text('+$hidden more in Bikes'),
              ),
            ),
        ],
      ],
    );

    final header = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.pedal_bike_rounded, color: _green, size: 18),
        ),
        const SizedBox(width: 10),
        const Text(
          'Fleet health',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        if (maintenance > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.build_rounded, size: 12, color: cs.error),
                const SizedBox(width: 4),
                Text(
                  '$maintenance need${maintenance == 1 ? 's' : ''} attention',
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
        const Spacer(),
        TextButton(onPressed: onOpenBikes, child: const Text('Manage bikes')),
      ],
    );

    return _Panel(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 280, child: summary),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: VerticalDivider(
                          width: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      Expanded(child: attention),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                summary,
                Divider(
                  height: 24,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                attention,
              ],
            ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.bike, required this.onTap});

  final Bike bike;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _bikeStatusColor(bike.status, cs);
    final label = bike.label?.trim().isNotEmpty == true ? bike.label! : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.build_rounded, size: 15, color: color),
                  const SizedBox(width: 10),
                  Text(
                    bike.code,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _bikeStatusLabel(bike.status),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttentionEmpty extends StatelessWidget {
  const _AttentionEmpty({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Today ─────────────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.week, required this.fill});

  final ReportSnapshot? week;

  /// Stretch the trend chart to the card height (wide layout).
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final daily = week?.daily ?? const <ReportDayPoint>[];
    final today = daily.isEmpty ? null : daily.last;

    Widget chartFor(double height) {
      if (daily.isEmpty) {
        final darkEmpty = Theme.of(context).brightness == Brightness.dark;
        return SizedBox(
          height: height,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No rides this week',
              style: TextStyle(
                color: darkEmpty
                    ? Colors.white.withValues(alpha: 0.7)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        );
      }
      final darkChart = Theme.of(context).brightness == Brightness.dark;
      return ReportLineChart(
        height: height,
        showAxes: false,
        onDark: darkChart,
        labels: [for (final d in daily) DateFormat('EEE').format(d.day)],
        series: [
          ReportLineSeries(
            label: 'Rides',
            color: darkChart ? Colors.white : QrideBrand.accent,
            values: [for (final d in daily) d.completed.toDouble()],
          ),
        ],
        tooltipTitle: (i) => DateFormat('EEEE, MMM d').format(daily[i].day),
        tooltipLines: (i) => [
          (
            label: 'Rides',
            value: '${daily[i].completed}',
            color: const Color(0xFF22C55E),
          ),
          (
            label: 'Collected',
            value: _pesoExact.format(daily[i].collected),
            color: _pink,
          ),
        ],
      );
    }

    final rides = today?.completed ?? 0;
    final collected = _peso.format(today?.collected ?? 0);
    final rideTime = (today?.rideMinutes ?? 0) <= 0
        ? '0m'
        : formatRideDurationMinutes(today!.rideMinutes);
    final yesterday = daily.length >= 2 ? daily[daily.length - 2] : null;
    final rideDelta =
        yesterday == null ? null : rides - yesterday.completed;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final ink = isDark ? Colors.white : cs.onSurface;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.75)
        : cs.onSurfaceVariant;

    final stats = Row(
      children: [
        Expanded(child: _todayStat('$rides', 'Rides', isDark)),
        const SizedBox(width: 8),
        Expanded(child: _todayStat(collected, 'Collected', isDark)),
        const SizedBox(width: 8),
        Expanded(child: _todayStat(rideTime, 'Ride time', isDark)),
      ],
    );

    return GlassPanel(
      tint: isDark ? const Color(0xB30A4DB8) : null,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Today',
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('EEE, MMM d').format(DateTime.now()),
                style: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          stats,
          if (rideDelta != null) ...[
            const SizedBox(height: 8),
            Text(
              rideDelta == 0
                  ? 'Same rides as yesterday'
                  : '${rideDelta > 0 ? '+' : ''}$rideDelta rides vs yesterday',
              style: TextStyle(
                color: muted,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'This week',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          if (fill)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    chartFor(constraints.maxHeight),
              ),
            )
          else
            chartFor(96),
        ],
      ),
    );
  }

  static Widget _todayStat(String value, String label, bool onDark) {
    final valueColor = onDark ? Colors.white : const Color(0xFF0F2744);
    final labelColor = onDark
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF5B6B80);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: onDark
            ? Colors.white.withValues(alpha: 0.14)
            : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: -0.4,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared panels ─────────────────────────────────────────────────────────────

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      onTap: onTap,
      padding: padding,
      child: child,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.hint,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
    this.alert = false,
  });

  final String label;
  final String hint;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (alert) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      height: 1.05,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.empty,
    required this.emptyIcon,
    required this.items,
    required this.kind,
    required this.onSeeAll,
  });

  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final String empty;
  final IconData emptyIcon;
  final List<RentalWithBike> items;
  final String kind;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              const SizedBox(width: 8),
              if (count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 12, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    emptyIcon,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    empty,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            ...items.map((r) => _QueueTile(row: r, kind: kind, color: color)),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.row, required this.kind, required this.color});

  final RentalWithBike row;
  final String kind;
  final Color color;

  String _since(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m ago';
    return DateFormat('MMM d, h:mm a').format(t.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rider = row.riderDisplay;
    final initial = rider.isEmpty ? '?' : rider.characters.first.toUpperCase();
    final since = kind == 'active'
        ? (row.rental.approvedAt ?? row.rental.startedAt)
        : row.rental.startedAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            child: Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rider,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  row.bikeDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              _since(since),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
