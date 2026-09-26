part of 'admin_dashboard_screen.dart';

class _BikesTab extends StatefulWidget {
  const _BikesTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_BikesTab> createState() => _BikesTabState();
}

class _BikesTabState extends State<_BikesTab> {
  late Future<List<Bike>> _future = widget.repo.fetchBikes();
  String? _statusFilter;
  bool _newestFirst = false;

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repo.fetchBikes();
    });
    await _future;
  }

  Future<void> _openQrGenerator({Bike? bike}) async {
    final refresh = await showAdminPage<bool>(
      context,
      maxWidth: 620,
      builder: (_) => AdminGenerateQrScreen(
        repo: widget.repo,
        initialBike: bike,
      ),
    );
    if (refresh == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = adminWide(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Bike>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(
                title: 'Could not load bikes',
                error: snapshot.error,
                onRetry: _refresh,
              );
            }
            final bikes = snapshot.data ?? const <Bike>[];
            final filtered = bikes
                .where(
                  (b) => _statusFilter == null || b.status == _statusFilter,
                )
                .toList();
            if (_newestFirst) {
              filtered.sort((a, b) {
                final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                return bt.compareTo(at);
              });
            } else {
              filtered.sort(
                (a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()),
              );
            }
            if (bikes.isEmpty) {
              return _EmptyState(
                icon: Icons.directions_bike_outlined,
                title: 'No bikes yet',
                subtitle: 'Create a bike and print its QR code to get started.',
                action: FilledButton.icon(
                  onPressed: () => _openQrGenerator(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New bike & QR'),
                ),
              );
            }

            return ListView(
              padding: adminPagePadding(context),
              children: [
                AdminContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdminPageHeader(
                        title: 'Bikes',
                        subtitle:
                            '${bikes.length} in the fleet · tap the menu to set maintenance',
                        trailing: wide
                            ? FilledButton.icon(
                                onPressed: () => _openQrGenerator(),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('New bike & QR'),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _StatusFilterBar(
                              selected: _statusFilter,
                              onSelected: (s) =>
                                  setState(() => _statusFilter = s),
                            ),
                          ),
                          const SizedBox(width: 12),
                          AdminSortToggle(
                            newestFirst: _newestFirst,
                            onChanged: (newest) =>
                                setState(() => _newestFirst = newest),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No bikes match this filter.',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        AdminCardGrid(
                          minItemWidth: 340,
                          spacing: 12,
                          children: [
                            for (final bike in filtered)
                              _BikeCard(
                                bike: bike,
                                onQr: () => _openQrGenerator(bike: bike),
                                onStatusChange: (status) async {
                                  await widget.repo.updateBikeStatus(
                                    bikeId: bike.id,
                                    status: status,
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Status updated to $status'),
                                    ),
                                  );
                                  await _refresh();
                                },
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: wide
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openQrGenerator(),
              icon: const Icon(Icons.pedal_bike_outlined),
              label: const Text('New bike & QR'),
            ),
    );
  }
}

class _ActiveRentalsTab extends StatefulWidget {
  const _ActiveRentalsTab({required this.repo, this.changes});
  final AdminRepository repo;
  final Listenable? changes;

  @override
  State<_ActiveRentalsTab> createState() => _ActiveRentalsTabState();
}

class _ActiveRentalsTabState extends State<_ActiveRentalsTab> {
  late Future<List<RentalWithBike>> _future = widget.repo.fetchActiveRentalsWithBikes();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_onLive);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _onLive());
  }

  @override
  void didUpdateWidget(covariant _ActiveRentalsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes?.removeListener(_onLive);
      widget.changes?.addListener(_onLive);
    }
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_onLive);
    _poll?.cancel();
    super.dispose();
  }

  void _onLive() {
    if (mounted) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repo.fetchActiveRentalsWithBikes();
    });
    await _future;
  }

  Future<void> _endRental(RentalWithBike row) async {
    final r = row.rental;
    final now = DateTime.now();
    final approvedAt = r.approvedAt ?? r.startedAt;
    final elapsedMin = now.difference(approvedAt).inSeconds / 60.0;
    final overtimeMin = (elapsedMin - r.plannedMinutes).clamp(0.0, double.infinity);
    final baseCost = (r.plannedMinutes / 60.0) * r.ratePerHour;
    final penalty = (overtimeMin / 60.0) * r.ratePerHour * 1.5;
    final totalCost = baseCost + penalty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End rental?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rider: ${row.riderDisplay}'),
            Text('Bike: ${row.bikeDisplay}'),
            const SizedBox(height: 10),
            Text('Rental charge:  ₱${baseCost.toStringAsFixed(2)}'),
            if (penalty > 0)
              Text(
                'Penalty fee: ₱${penalty.toStringAsFixed(2)} '
                '(${overtimeMin.toInt()} min overtime)',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            Text(
              'Total: ₱${totalCost.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End rental'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await widget.repo.endRentalByAdmin(
        rentalId: r.id,
        actualCost: totalCost,
        penaltyFee: penalty,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rental ended. Total: ₱${totalCost.toStringAsFixed(2)}',
          ),
        ),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<RentalWithBike>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              title: 'Could not load active rentals',
              error: snapshot.error,
              onRetry: _refresh,
            );
          }
          final rentals = snapshot.data ?? const <RentalWithBike>[];
          if (rentals.isEmpty) {
            return _EmptyState(
              icon: Icons.play_circle_outline,
              title: 'No active rentals',
              subtitle: 'Approved rentals appear here. Pull to refresh.',
              action: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            );
          }

          return ListView(
            padding: adminPagePadding(context),
            children: [
              AdminContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminPageHeader(
                      title: 'Active rentals',
                      subtitle:
                          '${rentals.length} ride${rentals.length == 1 ? '' : 's'} in progress',
                      trailing: IconButton(
                        tooltip: 'Refresh',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AdminCardGrid(
                      minItemWidth: 380,
                      spacing: 12,
                      children: [
                        for (final row in rentals)
                          Builder(builder: (context) {
              final r = row.rental;
              // For stale rentals without an approved_at, the timer is meaningless.
              // We still show the row so admin can end it, but don't compute overtime.
              final hasApproval = r.approvedAt != null;
              final approvedAt = r.approvedAt ?? r.startedAt;
              final endTime = approvedAt.add(Duration(minutes: r.plannedMinutes));
              final now = DateTime.now();
              final isOvertime = hasApproval && now.isAfter(endTime);
              final remaining = endTime.difference(now);
              final df = DateFormat('h:mm a');

              return GlassPanel(
                radius: 20,
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Rider + bike
                      Row(
                        children: [
                          Icon(Icons.directions_bike_outlined,
                              color: cs.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.bikeDisplay,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Rider: ${row.riderDisplay}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!hasApproval)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'STALE',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          else if (isOvertime)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'OVERTIME',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          _InfoPair(
                            label: 'Started',
                            value: df.format(approvedAt.toLocal()),
                          ),
                          _InfoPair(
                            label: 'Ends at',
                            value: df.format(endTime.toLocal()),
                          ),
                          _InfoPair(
                            label: isOvertime ? 'Overtime' : 'Remaining',
                            value: isOvertime
                                ? '+${now.difference(endTime).inMinutes}m'
                                : '${remaining.inMinutes}m ${remaining.inSeconds % 60}s',
                            valueColor: isOvertime ? cs.error : null,
                          ),
                          _InfoPair(
                            label: 'Plan',
                            value: '${r.plannedMinutes}min '
                                '· ₱${r.ratePerHour.toStringAsFixed(0)}/hr',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final loc = await widget.repo
                                    .fetchLastLocationForRental(r.id);
                                if (!context.mounted) return;
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => _RentalDetailDialog(
                                    rental: r,
                                    bike: row.bike,
                                    location: loc,
                                    username: row.riderDisplay,
                                  ),
                                );
                              },
                              child: const Text('Location'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.error,
                                foregroundColor: cs.onError,
                              ),
                              onPressed: () => _endRental(row),
                              child: const Text('End rental'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              );
                          }),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

