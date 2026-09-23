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
        _available = bikes.where((b) => b.status == 'available').length;
        _rented = bikes.where((b) => b.status == 'rented').length;
        _maintenance = bikes.where((b) => b.status == 'maintenance').length;
        _active = active.length;
        _pending = pending.take(4).toList();
        _rides = active.take(4).toList();
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
    final hour = DateTime.now().hour;
    final hello = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return RefreshIndicator(
      onRefresh: _load,
      color: QrideBrand.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            hello,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Campus overview',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 20),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final cards = [
                  _KpiCard(
                    label: 'Pending requests',
                    value: '${widget.pendingCount}',
                    icon: Icons.inbox_outlined,
                    color: const Color(0xFFD97706),
                    onTap: () => widget.onOpenTab(2),
                  ),
                  _KpiCard(
                    label: 'Active rides',
                    value: '$_active',
                    icon: Icons.near_me_rounded,
                    color: QrideBrand.accent,
                    onTap: () => widget.onOpenTab(3),
                  ),
                  _KpiCard(
                    label: 'Bikes available',
                    value: '$_available',
                    icon: Icons.pedal_bike_rounded,
                    color: const Color(0xFF16A34A),
                    onTap: () => widget.onOpenTab(1),
                  ),
                  _KpiCard(
                    label: 'Out on rent',
                    value: '$_rented',
                    icon: Icons.directions_bike_rounded,
                    color: QrideBrand.accentDeep,
                    onTap: () => widget.onOpenTab(1),
                  ),
                ];
                if (wide) {
                  return Row(
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
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
              const SizedBox(height: 12),
              Material(
                color: cs.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: Icon(Icons.build_rounded, color: cs.error),
                  title: Text(
                    '$_maintenance bike${_maintenance == 1 ? '' : 's'} in maintenance',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => widget.onOpenTab(1),
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Quick actions',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ActionChip(
                  icon: Icons.map_outlined,
                  label: 'Live map',
                  onTap: () => widget.onOpenTab(5),
                ),
                _ActionChip(
                  icon: Icons.inbox_outlined,
                  label: 'Review requests',
                  onTap: () => widget.onOpenTab(2),
                ),
                _ActionChip(
                  icon: Icons.badge_outlined,
                  label: 'Verify users',
                  onTap: () => widget.onOpenTab(6),
                ),
                _ActionChip(
                  icon: Icons.insights_outlined,
                  label: 'Reports',
                  onTap: () => widget.onOpenTab(7),
                ),
              ],
            ),
            const SizedBox(height: 28),
            _SectionHead(
              title: 'Waiting for approval',
              action: 'See all',
              onAction: () => widget.onOpenTab(2),
            ),
            const SizedBox(height: 10),
            if (_pending.isEmpty)
              _EmptyCard(
                icon: Icons.check_circle_outline_rounded,
                text: 'No pending rental requests.',
              )
            else
              ..._pending.map((r) => _QueueTile(row: r, kind: 'pending')),
            const SizedBox(height: 24),
            _SectionHead(
              title: 'Rides in progress',
              action: 'See all',
              onAction: () => widget.onOpenTab(3),
            ),
            const SizedBox(height: 10),
            if (_rides.isEmpty)
              _EmptyCard(
                icon: Icons.directions_bike_outlined,
                text: 'No active rides right now.',
              )
            else
              ..._rides.map((r) => _QueueTile(row: r, kind: 'active')),
          ],
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        color: color,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
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

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: QrideBrand.accent),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onPressed: onTap,
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const Spacer(),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
    final title = row.bikeDisplay;
    final who = row.riderDisplay;
    final when = DateFormat('h:mm a').format(row.rental.startedAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
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
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('$who · $when'),
        ),
      ),
    );
  }
}
