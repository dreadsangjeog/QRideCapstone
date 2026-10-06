part of 'admin_dashboard_screen.dart';

class _BikesTab extends StatefulWidget {
  const _BikesTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_BikesTab> createState() => _BikesTabState();
}

class _BikesTabState extends State<_BikesTab> {
  final _rateKey = GlobalKey<HourlyRateCardState>();
  late Future<List<Bike>> _future = widget.repo.fetchBikes();
  String? _statusFilter;
  bool _newestFirst = false;

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repo.fetchBikes();
    });
    await Future.wait([
      _future,
      _rateKey.currentState?.reload() ?? Future<void>.value(),
    ]);
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

  Future<void> _confirmDeleteBike(Bike bike) async {
    final name = bike.label?.trim().isNotEmpty == true
        ? bike.label!.trim()
        : 'Bike ${bike.code}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_forever_rounded, color: cs.error),
          title: const Text('Delete this bike?'),
          content: Text(
            'Remove $name (${bike.code}) from the fleet permanently.\n\n'
            'You cannot delete it while a rental is pending or active. '
            'Past rental history stays in reports as “Removed bike”.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete bike'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.repo.deleteBike(bike);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name deleted')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyDeleteError(e))),
      );
    }
  }

  String _friendlyDeleteError(Object e) {
    final s = e.toString();
    if (s.contains('pending or active') || s.contains('open rental')) {
      return 'End or reject the open rental on this bike before deleting it.';
    }
    if (s.contains('rented') || s.contains('End the active rental')) {
      return 'This bike is rented. End the rental first.';
    }
    if (s.contains('admin_delete_bike') || s.contains('PGRST202')) {
      return 'Delete is not set up on the database yet. Run migration 034_admin_delete_bike.sql in Supabase.';
    }
    return 'Could not delete bike: $e';
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
                final byTime = bt.compareTo(at);
                if (byTime != 0) return byTime;
                return compareNatural(bikeSortName(a), bikeSortName(b));
              });
            } else {
              filtered.sort((a, b) {
                final byName = compareNatural(bikeSortName(a), bikeSortName(b));
                if (byName != 0) return byName;
                return compareNatural(a.code, b.code);
              });
            }
            if (bikes.isEmpty) {
              return ListView(
                padding: adminPagePadding(context),
                children: [
                  AdminContent(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HourlyRateCard(key: _rateKey),
                        const SizedBox(height: 24),
                        _EmptyState(
                          icon: Icons.directions_bike_outlined,
                          title: 'No bikes yet',
                          subtitle:
                              'Create a bike and print its QR code to get started.',
                          action: FilledButton.icon(
                            onPressed: () => _openQrGenerator(),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('New bike & QR'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                            '${bikes.length} in the fleet · menu to set maintenance or delete',
                        trailing: wide
                            ? FilledButton.icon(
                                onPressed: () => _openQrGenerator(),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('New bike & QR'),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      HourlyRateCard(key: _rateKey),
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
                                onPhotoTap: () async {
                                  final updated = await showBikePhotoEditor(
                                    context,
                                    repo: widget.repo,
                                    bike: bike,
                                  );
                                  if (updated != null && context.mounted) {
                                    await _refresh();
                                  }
                                },
                                onStatusChange: (status) async {
                                  try {
                                    await widget.repo.updateBikeStatus(
                                      bikeId: bike.id,
                                      status: status,
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Could not update status: $e'),
                                      ),
                                    );
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Status updated to $status'),
                                    ),
                                  );
                                  await _refresh();
                                },
                                onDelete: () => _confirmDeleteBike(bike),
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

class _ActiveRentalsTabState extends State<_ActiveRentalsTab>
    with AdminSilentReload, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<RentalWithBike>? _rows;
  List<HourlyRateChange> _rateHistory = const [];
  Object? _error;
  Timer? _poll;
  Timer? _clock;
  Timer? _coalesce;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_onLive);
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _onLive());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_rows != null && _rows!.isNotEmpty) setState(() {});
    });
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
    _clock?.cancel();
    _coalesce?.cancel();
    super.dispose();
  }

  void _onLive() {
    _coalesce?.cancel();
    _coalesce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    await silentReload(() async {
      try {
        final rowsFuture = widget.repo.fetchActiveRentalsWithBikes();
        final historyFuture = RentalRepository().fetchRateHistory();
        final rows = await rowsFuture;
        final history = await historyFuture;
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _rateHistory = history;
          _error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          if (_rows == null) _error = e;
        });
      }
    });
  }

  final Set<String> _ending = {};

  Future<void> _endRental(RentalWithBike row) async {
    final r = row.rental;
    if (!_ending.add(r.id)) return;
    try {
      final history = await RentalRepository().fetchRateHistory();
      if (!mounted) return;
      final charge = await showDialog<RentalCharge>(
        context: context,
        builder: (_) => _EndRentalDialog(row: row, history: history),
      );
      if (charge == null || !mounted) return;
      try {
        await widget.repo.endRentalByAdmin(
          rentalId: r.id,
          actualCost: charge.total,
          penaltyFee: charge.penalty,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Rental ended. Total: ${formatPeso(charge.total)}',
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
    } finally {
      _ending.remove(r.id);
    }
  }

  String _planLabel(Rental r) {
    final quoted = roundPeso((r.plannedMinutes / 60.0) * r.ratePerHour);
    final booked = rentalChargeAt(r, DateTime.now(), _rateHistory).base;
    final whole = (r.ratePerHour * 100).round() % 100 == 0;
    final hourly = whole
        ? r.ratePerHour.toStringAsFixed(0)
        : r.ratePerHour.toStringAsFixed(2);
    if ((booked - quoted).abs() < 0.5) {
      return '${r.plannedMinutes}min · ₱$hourly/hr';
    }
    return '${r.plannedMinutes}min · ${formatPeso(booked)} booked';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: Builder(builder: (context) {
          if (_rows == null && _error != null) {
            return _ErrorState(
              title: 'Could not load active rentals',
              error: _error,
              onRetry: _refresh,
            );
          }
          if (_rows == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final rentals = _rows!;
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
                          '${rentals.length} ride${rentals.length == 1 ? '' : 's'} in progress · ending soonest first',
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
                          KeyedSubtree(
                            key: ValueKey(row.rental.id),
                            child: Builder(builder: (context) {
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
                            value: _planLabel(r),
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
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
    );
  }
}

/// Pops with the charge at the moment staff confirm, so the amount shown is
/// the amount billed even if the dialog stays open during overtime.
class _EndRentalDialog extends StatefulWidget {
  const _EndRentalDialog({required this.row, required this.history});

  final RentalWithBike row;
  final List<HourlyRateChange> history;

  @override
  State<_EndRentalDialog> createState() => _EndRentalDialogState();
}

class _EndRentalDialogState extends State<_EndRentalDialog> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row.rental;
    final now = DateTime.now();
    final charge = rentalChargeAt(r, now, widget.history);
    final overtimeMin = overtimeMinutesAt(r, now);
    return AlertDialog(
      title: const Text('End rental?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rider: ${widget.row.riderDisplay}'),
          Text('Bike: ${widget.row.bikeDisplay}'),
          const SizedBox(height: 10),
          Text('Rental charge:  ${formatPeso(charge.base)}'),
          if (charge.penalty > 0)
            Text(
              'Penalty fee: ${formatPeso(charge.penalty)} '
              '(${overtimeMin.round()} min overtime)',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            'Total: ${formatPeso(charge.total)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(rentalChargeAt(r, DateTime.now(), widget.history)),
          child: const Text('End rental'),
        ),
      ],
    );
  }
}

