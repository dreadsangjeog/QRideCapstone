import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/rental_with_bike.dart';
import '../../services/admin_repository.dart';
import '../../utils/peso.dart';
import '../../widgets/qride_glass.dart';
import 'admin_layout.dart';

part 'admin_requests_widgets.dart';

/// Shows pending rental requests that need admin approval.
class AdminRequestsTab extends StatefulWidget {
  const AdminRequestsTab({
    super.key,
    required this.repo,
    this.onQueueChanged,
  });

  final AdminRepository repo;
  final Future<void> Function()? onQueueChanged;

  @override
  State<AdminRequestsTab> createState() => AdminRequestsTabState();
}

class AdminRequestsTabState extends State<AdminRequestsTab>
    with AdminSilentReload, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<RentalWithBike>? _rows;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<List<RentalWithBike>> _load() => widget.repo.fetchPendingRentals();

  Future<void> refresh() async {
    await _reload();
    await widget.onQueueChanged?.call();
  }

  Future<void> _reload() async {
    await silentReload(() async {
      try {
        final rows = await _load();
        if (!mounted) return;
        setState(() {
          _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: refresh,
      child: _requestsBody(),
    );
  }

  Widget _requestsBody() {
    if (_rows == null && _error != null) {
      return _centred(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 52, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 10),
            Text(_error.toString()),
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
    if (_rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final requests = _rows!;
    if (requests.isEmpty) {
      return ListView(
        children: [
          _centred(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  'When a rider requests a bike, it will appear here for you to accept.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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

    return ListView(
      padding: adminPagePadding(context),
      children: [
        AdminContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminPageHeader(
                title: 'Rental requests',
                subtitle:
                    '${requests.length} waiting · oldest first · the bike is marked rented when you accept',
                trailing: IconButton(
                  tooltip: 'Refresh',
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 16),
              AdminCardGrid(
                minItemWidth: 360,
                spacing: 12,
                children: [
                  for (final row in requests)
                    _RequestCard(
                      key: ValueKey(row.rental.id),
                      row: row,
                      onApprove: () => _approve(row),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
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
