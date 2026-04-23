import 'package:flutter/material.dart';

import '../models/bike.dart';
import '../services/admin_repository.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../services/rental_repository.dart';
import '../widgets/user_portal_chrome.dart';

class UserActiveRentalScreen extends StatefulWidget {
  const UserActiveRentalScreen({super.key});

  @override
  State<UserActiveRentalScreen> createState() => _UserActiveRentalScreenState();
}

class _UserActiveRentalScreenState extends State<UserActiveRentalScreen> {
  final _rentalRepo = RentalRepository();
  final _adminRepo = AdminRepository();
  final _tracking = LocationTrackingService();

  String? _activeRentalId;
  Bike? _activeBike;
  bool _busy = false;

  Future<void> _ensureSignedIn() async {
    if (!AuthService.isSignedIn) {
      throw StateError('Please log in first.');
    }
  }

  Future<Bike?> _pickAvailableBike() async {
    final bikes = await _adminRepo.fetchBikes();
    final available = bikes.where((b) => b.status == 'available').toList();
    if (available.isEmpty) return null;

    if (!mounted) return null;
    final cs = Theme.of(context).colorScheme;
    return showDialog<Bike>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.pedal_bike_rounded,
          color: cs.primary,
          size: 28,
        ),
        title: const Text('Choose a bike'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final b in available)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(
                        Icons.directions_bike_outlined,
                        color: cs.primary,
                      ),
                      title: Text(
                        b.label?.trim().isNotEmpty == true
                            ? '${b.label} (${b.code})'
                            : 'Bike ${b.code}',
                      ),
                      onTap: () => Navigator.of(ctx).pop(b),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _startDemoRental() async {
    setState(() => _busy = true);
    try {
      await _ensureSignedIn();
      final bike = await _pickAvailableBike();
      if (bike == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No available bikes to rent.')),
        );
        return;
      }

      final rentalId = await _rentalRepo.startRental(bikeId: bike.id);
      await _tracking.startTracking(
        rentalId: rentalId,
        minInterval: const Duration(seconds: 45),
      );

      setState(() {
        _activeRentalId = rentalId;
        _activeBike = bike;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endDemoRental() async {
    final rentalId = _activeRentalId;
    final bike = _activeBike;
    if (rentalId == null || bike == null) return;

    setState(() => _busy = true);
    try {
      await _tracking.stopTracking();
      await _rentalRepo.endRental(rentalId: rentalId);
      setState(() {
        _activeRentalId = null;
        _activeBike = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _tracking.stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final hasActive = _activeRentalId != null && _activeBike != null;
    final bikeLabel = _activeBike?.label?.trim().isNotEmpty == true
        ? '${_activeBike!.label} (${_activeBike!.code})'
        : (_activeBike != null ? 'Bike ${_activeBike!.code}' : '');

    return UserPortalScaffold(
      title: 'Active rental',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: hasActive
                              ? cs.primaryContainer.withValues(alpha: 0.85)
                              : cs.surfaceContainerHighest.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasActive
                                ? cs.primary.withValues(alpha: 0.22)
                                : cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Icon(
                          hasActive
                              ? Icons.near_me_rounded
                              : Icons.directions_bike_rounded,
                          size: 30,
                          color: hasActive ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Tracking on',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              Text(
                                'Idle',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              hasActive
                                  ? 'Rental in progress'
                                  : 'No active rental',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    hasActive
                        ? 'Location updates are sent periodically. Admins can see your last known position on the map.'
                        : 'Scan a bike or start a demo rental here to create an active session and GPS points in Supabase.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  if (hasActive) ...[
                    const SizedBox(height: 18),
                    Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.pedal_bike_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                bikeLabel,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            ),
          if (!_busy && !hasActive) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _startDemoRental,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start demo rental'),
            ),
          ],
          if (!_busy && hasActive) ...[
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _endDemoRental,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('End rental'),
            ),
          ],
        ],
      ),
    );
  }
}
