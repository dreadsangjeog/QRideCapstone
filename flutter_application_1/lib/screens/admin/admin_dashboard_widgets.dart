part of 'admin_dashboard_screen.dart';

// ── Stat card (Reports tab) ───────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.sub,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              sub,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Info pair (Active rentals tab) ────────────────────────────────────────────

class _InfoPair extends StatelessWidget {
  const _InfoPair({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab({required this.repo});
  final AnalyticsRepository repo;

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  int _days = 7;
  late Future<UtilizationStats> _future = _load();
  bool _exporting = false;

  Future<UtilizationStats> _load() => widget.repo.utilizationLastDays(_days);

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final csv = await widget.repo.buildEndedRentalsExportCsv(_days);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          text: csv,
          subject: 'QRide rental analytics (last $_days days)',
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
      child: FutureBuilder<UtilizationStats>(
        key: ValueKey<int>(_days),
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              children: [
                const SizedBox(height: 120),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _ErrorState(
                  title: 'Could not load utilization',
                  error: snapshot.error,
                  onRetry: _refresh,
                ),
              ],
            );
          }
          final stats = snapshot.data!;
          final avg = stats.averageDuration;
          final sortedDays = stats.rentalsPerDay.keys.toList()
            ..sort();

          final avgText = avg == null
              ? '—'
              : '${avg.inMinutes} min  ·  ${(avg.inSeconds / 3600).toStringAsFixed(2)} h';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // ── Range selector ────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Period',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7,  label: Text('7 days')),
                        ButtonSegment(value: 14, label: Text('14 days')),
                        ButtonSegment(value: 30, label: Text('30 days')),
                      ],
                      selected: {_days},
                      onSelectionChanged: (Set<int> s) {
                        setState(() {
                          _days = s.first;
                          _future = _load();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _exporting ? null : _exportCsv,
                  icon: _exporting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onSecondaryContainer,
                          ),
                        )
                      : const Icon(Icons.ios_share_rounded, size: 20),
                  label: Text(_exporting ? 'Preparing…' : 'Export CSV'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Avg duration counts ride time from approval (or request start if no approval).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // ── Stat row ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.receipt_long_rounded,
                      iconColor: cs.primary,
                      label: 'Total rentals',
                      value: '${stats.totalEndedRentals}',
                      sub: 'last ${_days}d',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.timer_outlined,
                      iconColor: cs.tertiary,
                      label: 'Avg duration',
                      value: avg == null ? '—' : '${avg.inMinutes}m',
                      sub: avgText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Rentals per day ───────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.bar_chart_rounded,
                              color: cs.onSecondaryContainer,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Rentals per day',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (sortedDays.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No completed rentals in this window.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        for (final d in sortedDays) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    DateFormat('EEE, MMM d').format(d),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${stats.rentalsPerDay[d] ?? 0}',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (d != sortedDays.last)
                            Divider(
                              height: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                        ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Status helpers ──────────────────────────────────────────────────────────

Color _statusColor(String status, ColorScheme cs) => switch (status) {
      'available'   => const Color(0xFF22C55E),
      'rented'      => cs.primary,
      'maintenance' => cs.error,
      _             => cs.onSurfaceVariant,
    };

IconData _statusIcon(String status) => switch (status) {
      'available'   => Icons.check_circle_rounded,
      'rented'      => Icons.directions_bike_rounded,
      'maintenance' => Icons.build_rounded,
      _             => Icons.help_outline,
    };

// ── Bike card ───────────────────────────────────────────────────────────────

class _BikeCard extends StatelessWidget {
  const _BikeCard({
    required this.bike,
    required this.onQr,
    required this.onStatusChange,
  });

  final Bike bike;
  final VoidCallback onQr;
  final ValueChanged<String> onStatusChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _statusColor(bike.status, cs);
    final name = bike.label?.trim().isNotEmpty == true
        ? bike.label!
        : 'Bike ${bike.code}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Colored left status bar
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Bike icon avatar
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        _statusIcon(bike.status),
                        color: color,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 13),
                    // Name + code
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Code: ${bike.code}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right side: badge + actions
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatusBadge(status: bike.status, cs: cs),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'QR code',
                              icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                              onPressed: onQr,
                              style: IconButton.styleFrom(
                                foregroundColor: cs.primary,
                              ),
                            ),
                            _StatusMenu(
                              status: bike.status,
                              onSelected: onStatusChange,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.cs});
  final String status;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status, cs);
    final label = status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Status filter bar ────────────────────────────────────────────────────────

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(String?, String, Color)>[
      (null,          'All',         cs.primary),
      ('available',   'Available',   const Color(0xFF22C55E)),
      ('rented',      'Rented',      cs.primary),
      ('maintenance', 'Maintenance', cs.error),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final (value, label, color) = item;
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onSelected(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSelected ? color : cs.onSurfaceVariant,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Status change menu ───────────────────────────────────────────────────────

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.status, required this.onSelected});

  final String status;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      onSelected: onSelected,
      icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.onSurfaceVariant),
      itemBuilder: (context) => [
        _menuItem('available',   'Available',   Icons.check_circle_rounded, const Color(0xFF22C55E)),
        _menuItem('maintenance', 'Maintenance', Icons.build_rounded, cs.error),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, String label, IconData icon, Color color) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _RentalDetailDialog extends StatelessWidget {
  const _RentalDetailDialog({
    required this.rental,
    required this.bike,
    required this.location,
    required this.username,
  });

  final Rental rental;
  final Bike? bike;
  final RentalLocation? location;
  final String username;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = location;
    final bikeLine = bike == null
        ? rental.bikeId
        : (bike!.label?.trim().isNotEmpty == true
            ? '${bike!.label} (${bike!.code})'
            : bike!.code);
    return AlertDialog(
      title: const Text('Rental details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bike: $bikeLine', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('Rider: $username'),
            Text('Started: ${DateFormat('MMM d, h:mm a').format(rental.startedAt)}'),
            const SizedBox(height: 12),
            Text(
              'Last known location',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            if (loc == null)
              const Text('No location has been recorded yet.')
            else ...[
              Text('Lat: ${loc.lat.toStringAsFixed(6)}'),
              Text('Lng: ${loc.lng.toStringAsFixed(6)}'),
              if (loc.accuracyM != null)
                Text('Accuracy: ${loc.accuracyM!.toStringAsFixed(0)} m'),
              Text(
                DateFormat('MMM d, h:mm a').format(loc.recordedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(icon, size: 44, color: cs.primary),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: cs.error),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error?.toString() ?? 'Unknown error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
