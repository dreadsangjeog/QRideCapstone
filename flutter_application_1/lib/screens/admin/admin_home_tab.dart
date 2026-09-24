import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/rental_with_bike.dart';
import '../../services/admin_repository.dart';
import '../../theme/brand.dart';

/// Overview home for admins — KPIs, shortcuts, and live queues.
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
  bool _loading = true;
  int _available = 0;
  int _rented = 0;
  int _maintenance = 0;
  int _active = 0;
  int _fleet = 0;
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
      final bikes = await widget.repo.fetchBikes();
      final pending = await widget.repo.fetchPendingRentals();
      final active = await widget.repo.fetchActiveRentalsWithBikes();
      if (!mounted) return;
      setState(() {
        _fleet = bikes.length;
        _available = bikes.where((b) => b.status == 'available').length;
        _rented = bikes.where((b) => b.status == 'rented').length;
        _maintenance = bikes.where((b) => b.status == 'maintenance').length;
        _active = active.length;
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
    final isDark = cs.brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width >= 980;

    return ColoredBox(
      color: cs.brightness == Brightness.dark
          ? QrideBrand.night
          : const Color(0xFFF3F6FB),
      child: RefreshIndicator(
        onRefresh: _load,
        color: QrideBrand.accent,
        child: ListView(
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
                        'Overview',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _fleet == 0
                            ? 'Campus fleet status'
                            : '$_fleet bikes in the campus fleet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final four = constraints.maxWidth >= 860;
                  final cards = [
                    _KpiCard(
                      label: 'Pending',
                      hint: 'Need approval',
                      value: '${widget.pendingCount}',
                      icon: Icons.inbox_rounded,
                      color: const Color(0xFFEA580C),
                      onTap: () => widget.onOpenTab(2),
                    ),
                    _KpiCard(
                      label: 'Active',
                      hint: 'Rides now',
                      value: '$_active',
                      icon: Icons.near_me_rounded,
                      color: QrideBrand.accent,
                      onTap: () => widget.onOpenTab(3),
                    ),
                    _KpiCard(
                      label: 'Available',
                      hint: 'Ready to rent',
                      value: '$_available',
                      icon: Icons.pedal_bike_rounded,
                      color: const Color(0xFF16A34A),
                      onTap: () => widget.onOpenTab(1),
                    ),
                    _KpiCard(
                      label: 'On rent',
                      hint: 'Out on campus',
                      value: '$_rented',
                      icon: Icons.directions_bike_rounded,
                      color: QrideBrand.accentDeep,
                      onTap: () => widget.onOpenTab(1),
                    ),
                  ];
                  if (four) {
                    return Row(
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(width: 14),
                          Expanded(child: cards[i]),
                        ],
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: cards[0]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[1]),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: cards[2]),
                          const SizedBox(width: 12),
                          Expanded(child: cards[3]),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (_maintenance > 0) ...[
                const SizedBox(height: 14),
                Material(
                  color: cs.errorContainer.withValues(alpha: isDark ? 0.35 : 0.55),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => widget.onOpenTab(1),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cs.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.build_rounded, color: cs.error),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$_maintenance bike${_maintenance == 1 ? '' : 's'} in maintenance',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Text(
                'Shortcuts',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final actions = [
                    _ShortcutTile(
                      icon: Icons.map_rounded,
                      label: 'Live map',
                      sub: 'Track riders',
                      onTap: () => widget.onOpenTab(5),
                    ),
                    _ShortcutTile(
                      icon: Icons.inbox_rounded,
                      label: 'Requests',
                      sub: 'Approve rentals',
                      onTap: () => widget.onOpenTab(2),
                    ),
                    _ShortcutTile(
                      icon: Icons.badge_rounded,
                      label: 'Users',
                      sub: 'Verify IDs',
                      onTap: () => widget.onOpenTab(6),
                    ),
                    _ShortcutTile(
                      icon: Icons.insights_rounded,
                      label: 'Reports',
                      sub: 'Usage stats',
                      onTap: () => widget.onOpenTab(7),
                    ),
                  ];
                  if (constraints.maxWidth >= 720) {
                    return Row(
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Expanded(child: actions[i]),
                        ],
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: actions
                        .map(
                          (a) => SizedBox(
                            width: (constraints.maxWidth - 10) / 2,
                            child: a,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 28),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _QueuePanel(
                        title: 'Waiting for approval',
                        empty: 'No pending rental requests.',
                        emptyIcon: Icons.check_circle_outline_rounded,
                        items: _pending,
                        kind: 'pending',
                        onSeeAll: () => widget.onOpenTab(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _QueuePanel(
                        title: 'Rides in progress',
                        empty: 'No active rides right now.',
                        emptyIcon: Icons.directions_bike_outlined,
                        items: _rides,
                        kind: 'active',
                        onSeeAll: () => widget.onOpenTab(3),
                      ),
                    ),
                  ],
                )
              else ...[
                _QueuePanel(
                  title: 'Waiting for approval',
                  empty: 'No pending rental requests.',
                  emptyIcon: Icons.check_circle_outline_rounded,
                  items: _pending,
                  kind: 'pending',
                  onSeeAll: () => widget.onOpenTab(2),
                ),
                const SizedBox(height: 16),
                _QueuePanel(
                  title: 'Rides in progress',
                  empty: 'No active rides right now.',
                  emptyIcon: Icons.directions_bike_outlined,
                  items: _rides,
                  kind: 'active',
                  onSeeAll: () => widget.onOpenTab(3),
                ),
              ],
            ],
          ],
        ),
      ),
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
  });

  final String label;
  final String hint;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.16),
                Theme.of(context).colorScheme.surface,
              ],
            ),
            border: Border.all(color: color.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 16),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: color,
                        height: 1,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: QrideBrand.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: QrideBrand.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({
    required this.title,
    required this.empty,
    required this.emptyIcon,
    required this.items,
    required this.kind,
    required this.onSeeAll,
  });

  final String title;
  final String empty;
  final IconData emptyIcon;
  final List<RentalWithBike> items;
  final String kind;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 18, 16, 18),
                child: Row(
                  children: [
                    Icon(emptyIcon, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        empty,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...items.map((r) => _QueueTile(row: r, kind: kind)),
          ],
        ),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.row, required this.kind});

  final RentalWithBike row;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final when = DateFormat('h:mm a').format(row.rental.startedAt.toLocal());
    return ListTile(
      contentPadding: const EdgeInsets.only(right: 8),
      leading: CircleAvatar(
        backgroundColor: QrideBrand.accent.withValues(alpha: 0.12),
        foregroundColor: QrideBrand.accent,
        child: Icon(
          kind == 'pending'
              ? Icons.hourglass_top_rounded
              : Icons.near_me_rounded,
          size: 20,
        ),
      ),
      title: Text(
        row.bikeDisplay,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${row.riderDisplay} · $when'),
    );
  }
}
