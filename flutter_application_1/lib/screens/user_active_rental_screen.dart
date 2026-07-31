import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/rental.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../services/notification_service.dart';
import '../services/rental_repository.dart';
import '../services/supabase_client.dart';
import '../widgets/user_portal_chrome.dart';

part 'user_active_rental_widgets.dart';

class UserActiveRentalScreen extends StatefulWidget {
  const UserActiveRentalScreen({super.key});

  @override
  State<UserActiveRentalScreen> createState() =>
      _UserActiveRentalScreenState();
}

class _UserActiveRentalScreenState extends State<UserActiveRentalScreen> {
  final _repo = RentalRepository();
  final _tracking = LocationTrackingService();

  // Live map
  final _mapController = MapController();
  bool _mapReady = false;
  bool _autoCentered = false;

  Rental? _rental;
  bool _loading = true;

  // Timer state
  Timer? _ticker;
  DateTime _now = DateTime.now();

  // Notification sentinels
  bool _notifiedApproved   = false;
  bool _notifiedFiveMin    = false;
  bool _notifiedOvertime   = false;
  bool _notifiedEnded      = false;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _channel?.unsubscribe();
    _tracking.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onPositionUpdate() {
    final pos = _tracking.position.value;
    if (pos == null || !_mapReady || _autoCentered) return;
    _autoCentered = true;
    _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
  }

  Future<void> _init() async {
    await _fetchRental();
    _subscribeRealtime();
  }

  Future<void> _fetchRental() async {
    if (!AuthService.isSignedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final rental = await _repo.fetchMyActiveRental();
      if (!mounted) return;
      setState(() {
        _rental = rental;
        _loading = false;
      });
      if (rental?.isActive == true) unawaited(_startTracking(rental!));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return;

    _channel = SupabaseClientProvider.client
        .channel('rental-user-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rentals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) => _onRentalChange(payload.newRecord),
        )
        .subscribe();
  }

  void _onRentalChange(Map<String, dynamic> record) {
    final updated = Rental.fromJson(record);
    if (!mounted) return;
    setState(() => _rental = updated);

    if (updated.isActive && !_notifiedApproved) {
      _notifiedApproved = true;
      NotificationService.notifyApproved(
        updated.bikeId, // bikeId used as fallback label
      );
      unawaited(_startTracking(updated));
    }

    if (updated.isEnded || updated.isRejected) {
      _stopTracking();
      _ticker?.cancel();

      if (updated.isEnded && !_notifiedEnded) {
        _notifiedEnded = true;
        NotificationService.notifyRentalEnded(
          totalCost: updated.actualCost ?? 0,
          penaltyFee: updated.penaltyFee ?? 0,
        );
      }
      if (updated.isRejected) {
        NotificationService.notifyRejected();
      }
    }
  }

  Future<void> _startTracking(Rental rental) async {
    // Start the ticker immediately so the UI countdown works even if GPS is slow.
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _checkTimerNotifications();
    });

    // React to GPS fixes by re-centering the map on the first one.
    _tracking.position.removeListener(_onPositionUpdate);
    _tracking.position.addListener(_onPositionUpdate);

    try {
      await _tracking.startTracking(
        rentalId: rental.id,
        minInterval: const Duration(seconds: 15),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location sharing failed: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _stopTracking() {
    _tracking.stopTracking();
    _ticker?.cancel();
    _ticker = null;
  }

  void _checkTimerNotifications() {
    final rental = _rental;
    if (rental == null || !rental.isActive) return;
    final endTime = rental.scheduledEndTime;
    if (endTime == null) return;

    final remaining = endTime.difference(_now);

    if (!_notifiedFiveMin &&
        remaining.inSeconds <= 300 &&
        remaining.inSeconds > 0) {
      _notifiedFiveMin = true;
      NotificationService.notifyFiveMinuteWarning();
    }

    if (!_notifiedOvertime && _now.isAfter(endTime)) {
      _notifiedOvertime = true;
      NotificationService.notifyOvertimeStarted();
    }
  }

  Future<void> _cancelPending() async {
    final rental = _rental;
    if (rental == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel request?'),
        content: const Text(
          'This will cancel your rental request and free the bike.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _repo.cancelPendingRental(rentalId: rental.id);
      if (!mounted) return;
      setState(() => _rental = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const UserPortalScaffold(
        title: 'Active rental',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final rental = _rental;
    if (rental == null) return _buildNoRental();
    if (rental.isPending) return _buildPending(rental);
    if (rental.isActive) return _buildActive(rental);
    return _buildReceipt(rental); // ended or rejected
  }

  // ---------------------------------------------------------------------------
  // No rental
  // ---------------------------------------------------------------------------

  Widget _buildNoRental() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return UserPortalScaffold(
      title: 'Active rental',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Icon(Icons.directions_bike_rounded,
                        size: 36, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No active rental',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Scan a bike QR code from the Scan tab to request a rental.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pending approval
  // ---------------------------------------------------------------------------

  Widget _buildPending(Rental rental) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final df = DateFormat('h:mm a');
    final hours = rental.plannedMinutes >= 60
        ? '${rental.plannedMinutes ~/ 60}h '
            '${rental.plannedMinutes % 60 > 0 ? "${rental.plannedMinutes % 60}m" : ""}'
        : '${rental.plannedMinutes}m';

    return UserPortalScaffold(
      title: 'Active rental',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Waiting for approval',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Request submitted',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 12),
                  _RentalInfoRow(
                    icon: Icons.timer_outlined,
                    label: 'Duration',
                    value: hours,
                  ),
                  _RentalInfoRow(
                    icon: Icons.attach_money_rounded,
                    label: 'Est. cost',
                    value:
                        '₱${(rental.estimatedCost ?? 0).toStringAsFixed(2)}',
                  ),
                  _RentalInfoRow(
                    icon: Icons.schedule_rounded,
                    label: 'Requested at',
                    value: df.format(rental.startedAt.toLocal()),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'The admin has been notified. Your ride will begin as soon as they approve.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
            ),
            onPressed: _cancelPending,
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Active rental — countdown + cost
  // ---------------------------------------------------------------------------

  Widget _buildActive(Rental rental) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final endTime = rental.scheduledEndTime;
    final isOvertime = endTime != null && _now.isAfter(endTime);

    Duration remaining = Duration.zero;
    if (endTime != null && !isOvertime) {
      remaining = endTime.difference(_now);
    }

    final elapsedCost = rental.currentCost(_now);
    final penalty = rental.penaltyAmount(_now);
    final totalCost = elapsedCost + penalty;

    final overtimeMin = rental.overtimeMinutes(_now);

    return UserPortalScaffold(
      title: 'Active rental',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          // Status card
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isOvertime
                              ? cs.errorContainer
                              : cs.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.near_me_rounded,
                          color: isOvertime
                              ? cs.onErrorContainer
                              : cs.onPrimaryContainer,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: isOvertime
                                    ? cs.errorContainer
                                    : cs.primaryContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                isOvertime ? 'OVERTIME' : 'Tracking on',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isOvertime
                                      ? cs.onErrorContainer
                                      : cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isOvertime
                                  ? 'Rental time expired'
                                  : 'Rental in progress',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Countdown / Overtime display
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 18, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isOvertime
                          ? cs.errorContainer.withValues(alpha: 0.3)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isOvertime
                            ? cs.error.withValues(alpha: 0.3)
                            : cs.outlineVariant,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          isOvertime ? 'Overtime' : 'Time remaining',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isOvertime
                              ? '+${overtimeMin}m ${_now.difference(endTime).inSeconds % 60}s'
                              : '${remaining.inHours > 0 ? "${remaining.inHours}h " : ""}${remaining.inMinutes % 60}m ${remaining.inSeconds % 60}s',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isOvertime ? cs.error : cs.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (endTime != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            isOvertime
                                ? 'Scheduled end: ${DateFormat("h:mm a").format(endTime.toLocal())}'
                                : 'Ends at ${DateFormat("h:mm a").format(endTime.toLocal())}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Cost breakdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      children: [
                        _CostRow(label: 'Base cost', value: elapsedCost),
                        if (penalty > 0) ...[
                          _CostRow(
                            label:
                                'Penalty (${overtimeMin}m overtime × 1.5×)',
                            value: penalty,
                            color: cs.error,
                          ),
                          const Divider(height: 16),
                          _CostRow(
                            label: 'Total so far',
                            value: totalCost,
                            bold: true,
                          ),
                        ] else
                          _CostRow(
                            label: 'Total so far',
                            value: totalCost,
                            bold: true,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'Admin will end your ride. Location updates are sent every 15 seconds.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Live location map
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.map_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Live location',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      _GpsStatusBadge(tracking: _tracking),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 220,
                      child: _RiderLiveMap(
                        controller: _mapController,
                        tracking: _tracking,
                        onMapReady: () {
                          _mapReady = true;
                          _onPositionUpdate();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _GpsDetailRow(tracking: _tracking),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Receipt — ended or rejected
  // ---------------------------------------------------------------------------

  Widget _buildReceipt(Rental rental) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final df = DateFormat('MMM d, h:mm a');
    final isRejected = rental.isRejected;

    final totalCost = rental.actualCost ?? rental.estimatedCost ?? 0;
    final penalty = rental.penaltyFee ?? 0;
    final base = totalCost - penalty;

    return UserPortalScaffold(
      title: 'Active rental',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: isRejected
                            ? cs.errorContainer
                            : cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        isRejected
                            ? Icons.cancel_outlined
                            : Icons.check_circle_outline_rounded,
                        size: 36,
                        color: isRejected
                            ? cs.onErrorContainer
                            : cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isRejected ? 'Request declined' : 'Rental complete',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (!isRejected) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    _CostRow(label: 'Base fare', value: base),
                    if (penalty > 0)
                      _CostRow(
                        label: 'Penalty',
                        value: penalty,
                        color: cs.error,
                      ),
                    const Divider(height: 20),
                    _CostRow(label: 'Total', value: totalCost, bold: true),
                    if (rental.endedAt != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Ended at ${df.format(rental.endedAt!.toLocal())}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'The bike has been made available again. Try requesting a different bike.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: () => setState(() => _rental = null),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
