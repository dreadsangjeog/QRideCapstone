import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/rental_with_bike.dart';
import '../../services/admin_repository.dart';

part 'admin_requests_widgets.dart';

/// Shows pending rental requests that need admin approval or rejection.
class AdminRequestsTab extends StatefulWidget {
  const AdminRequestsTab({super.key, required this.repo});

  final AdminRepository repo;

  @override
  State<AdminRequestsTab> createState() => AdminRequestsTabState();
}

class AdminRequestsTabState extends State<AdminRequestsTab> {
  late Future<List<RentalWithBike>> _future = _load();

  Future<List<RentalWithBike>> _load() => widget.repo.fetchPendingRentals();

  Future<void> refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _approve(RentalWithBike row) async {
    try {
      await widget.repo.approveRental(row.rental.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved rental for ${row.riderDisplay}'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      await refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _reject(RentalWithBike row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject request?'),
        content: Text(
          'This will free the bike and notify ${row.riderDisplay} that their request was declined.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repo.rejectRental(row.rental.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
      await refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: refresh,
      child: FutureBuilder<List<RentalWithBike>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _centred(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 52,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 10),
                  Text(snapshot.error.toString()),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return ListView(
              children: [
                _centred(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        'No pending requests',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When a rider requests a bike, it will appear here for your approval.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (context, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _RequestCard(
              row: requests[i],
              onApprove: () => _approve(requests[i]),
              onReject: () => _reject(requests[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _centred({required Widget child}) => SizedBox(
        height: 400,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: child,
          ),
        ),
      );
}
