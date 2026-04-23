import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/bike.dart';
import '../../models/rental.dart';
import '../../models/rental_location.dart';
import '../../models/rental_with_bike.dart';
import 'admin_generate_qr_screen.dart';
import 'admin_map_tab.dart';
import '../../services/admin_repository.dart';
import '../../services/analytics_repository.dart';
import '../../services/auth_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  static const routeName = '/admin';

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminRepository();
  bool _adminGatePassed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAdmin());
  }

  Future<void> _ensureAdmin() async {
    final ok = await AuthService.isAdmin();
    if (!mounted) return;
    if (!ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Access denied'),
          content: const Text(
            'The admin dashboard is only available to accounts with the administrator role in QRide.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _adminGatePassed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminGatePassed) {
      return Scaffold(
        appBar: AppBar(title: const Text('QRide Admin')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('QRide Admin'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Bikes', icon: Icon(Icons.directions_bike_outlined)),
              Tab(text: 'Active', icon: Icon(Icons.play_circle_outline)),
              Tab(text: 'Map', icon: Icon(Icons.map_outlined)),
              Tab(text: 'Reports', icon: Icon(Icons.insights_outlined)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BikesTab(repo: _repo),
            _ActiveRentalsTab(repo: _repo),
            AdminMapTab(repo: _repo),
            _ReportsTab(repo: AnalyticsRepository()),
          ],
        ),
      ),
    );
  }
}

class _BikesTab extends StatefulWidget {
  const _BikesTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_BikesTab> createState() => _BikesTabState();
}

class _BikesTabState extends State<_BikesTab> {
  late Future<List<Bike>> _future = widget.repo.fetchBikes();
  String? _statusFilter;

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repo.fetchBikes();
    });
    await _future;
  }

  Future<void> _openQrGenerator({Bike? bike}) async {
    final refresh = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AdminGenerateQrScreen(
          repo: widget.repo,
          initialBike: bike,
        ),
      ),
    );
    if (refresh == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
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
          if (bikes.isEmpty) {
            return _EmptyState(
              icon: Icons.directions_bike_outlined,
              title: 'No bikes found',
              subtitle: 'Add bikes in Supabase to manage availability here.',
              action: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            );
          }
          if (filtered.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _statusFilter == null,
                      onSelected: (_) =>
                          setState(() => _statusFilter = null),
                    ),
                    for (final s in ['available', 'rented', 'maintenance'])
                      ChoiceChip(
                        label: Text(s),
                        selected: _statusFilter == s,
                        onSelected: (_) => setState(() => _statusFilter = s),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'No bikes match this filter.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length + 1,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _statusFilter == null,
                      onSelected: (_) =>
                          setState(() => _statusFilter = null),
                    ),
                    for (final s in ['available', 'rented', 'maintenance'])
                      ChoiceChip(
                        label: Text(s),
                        selected: _statusFilter == s,
                        onSelected: (_) => setState(() => _statusFilter = s),
                      ),
                  ],
                );
              }
              final bike = filtered[index - 1];
              return Card(
                child: ListTile(
                  title: Text(bike.label?.trim().isNotEmpty == true
                      ? bike.label!
                      : 'Bike ${bike.code}'),
                  subtitle: Text('Code: ${bike.code}'),
                  leading: _StatusIcon(status: bike.status),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Generate QR',
                        icon: const Icon(Icons.qr_code_2_outlined),
                        onPressed: () => _openQrGenerator(bike: bike),
                      ),
                      _StatusMenu(
                        status: bike.status,
                        onSelected: (status) async {
                          await widget.repo.updateBikeStatus(
                            bikeId: bike.id,
                            status: status,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Bike status set to $status'),
                            ),
                          );
                          await _refresh();
                        },
                      ),
                    ],
                  ),
                  tileColor: theme.colorScheme.surface,
                ),
              );
            },
          );
        },
      ),
    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openQrGenerator(),
        icon: const Icon(Icons.pedal_bike_outlined),
        label: const Text('New bike & QR'),
      ),
    );
  }
}

class _ActiveRentalsTab extends StatefulWidget {
  const _ActiveRentalsTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_ActiveRentalsTab> createState() => _ActiveRentalsTabState();
}

class _ActiveRentalsTabState extends State<_ActiveRentalsTab> {
  late Future<List<RentalWithBike>> _future = widget.repo.fetchActiveRentalsWithBikes();

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repo.fetchActiveRentalsWithBikes();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, h:mm a');
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
              subtitle: 'When someone starts a rental, it will show up here.',
              action: OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rentals.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final row = rentals[index];
              final r = row.rental;
              final bike = row.bike;
              final bikeLabel = bike == null
                  ? r.bikeId
                  : (bike.label?.trim().isNotEmpty == true
                      ? '${bike.label} (${bike.code})'
                      : bike.code);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.directions_bike_outlined),
                  title: Text(bikeLabel),
                  subtitle: Text(
                    'Started: ${df.format(r.startedAt)} · User ${r.userId}',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final loc =
                          await widget.repo.fetchLastLocationForRental(r.id);
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (context) => _RentalDetailDialog(
                          rental: r,
                          bike: bike,
                          location: loc,
                        ),
                      );
                    },
                    child: const Text('Details'),
                  ),
                ),
              );
            },
          );
        },
      ),
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

  Future<UtilizationStats> _load() => widget.repo.utilizationLastDays(_days);

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<UtilizationStats>(
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text(
                    'Range',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 7, label: Text('7d')),
                        ButtonSegment(value: 14, label: Text('14d')),
                        ButtonSegment(value: 30, label: Text('30d')),
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
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Utilization',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ended rentals (${_days}d)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${stats.totalEndedRentals}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Avg duration (ended rentals)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        avg == null
                            ? '—'
                            : '${avg.inMinutes} min (${(avg.inSeconds / 3600).toStringAsFixed(2)} h)',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rentals per day',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (sortedDays.isEmpty)
                        Text(
                          'No completed rentals in this window.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        for (final d in sortedDays)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    DateFormat('MMM d').format(d),
                                  ),
                                ),
                                Text(
                                  '${stats.rentalsPerDay[d] ?? 0}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
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
          );
        },
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (status) {
      'available' => (Icons.check_circle_outline, cs.primary),
      'rented' => (Icons.schedule, cs.tertiary),
      'maintenance' => (Icons.build_outlined, cs.error),
      _ => (Icons.help_outline, cs.onSurfaceVariant),
    };
    return Icon(icon, color: color);
  }
}

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({required this.status, required this.onSelected});

  final String status;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Change status',
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'available', child: Text('Available')),
        PopupMenuItem(value: 'rented', child: Text('Rented')),
        PopupMenuItem(value: 'maintenance', child: Text('Maintenance')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status),
          const SizedBox(width: 6),
          const Icon(Icons.expand_more),
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
  });

  final Rental rental;
  final Bike? bike;
  final RentalLocation? location;

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
            Text('Rental ID: ${rental.id}'),
            Text('User: ${rental.userId}'),
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
