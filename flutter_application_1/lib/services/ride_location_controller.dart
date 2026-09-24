import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_tracking_service.dart';
import 'rental_repository.dart';
import 'supabase_client.dart';

/// Keeps rental GPS writes alive for the whole ride, not just one screen.
class RideLocationController with WidgetsBindingObserver {
  RideLocationController({
    RentalRepository? repo,
    LocationTrackingService? tracking,
  }) : _repo = repo ?? RentalRepository(),
       tracking = tracking ?? LocationTrackingService();

  final RentalRepository _repo;
  final LocationTrackingService tracking;

  RealtimeChannel? _channel;
  Timer? _poll;
  String? _rentalId;
  bool _started = false;

  String? get rentalId => _rentalId;
  bool get isSharing => _rentalId != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await _sync();
    _subscribe();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_sync());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_sync());
        unawaited(tracking.resumeFromBackground());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Screen off or another app — keep GPS sharing.
        unawaited(tracking.keepSharingWithScreenOff());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _sync() async {
    try {
      final rental = await _repo.fetchMyActiveRental();
      if (rental != null && rental.isActive) {
        if (_rentalId == rental.id) return;
        _rentalId = rental.id;
        await tracking.startTracking(
          rentalId: rental.id,
          minInterval: const Duration(seconds: 5),
        );
        return;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RideLocation] sync failed: $e');
      return;
    }

    if (_rentalId == null) return;
    _rentalId = null;
    await tracking.stopTracking();
  }

  void _subscribe() {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return;

    _channel = SupabaseClientProvider.client
        .channel('ride-location-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rentals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => unawaited(_sync()),
        )
        .subscribe();
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _poll = null;
    await _channel?.unsubscribe();
    _channel = null;
    _rentalId = null;
    _started = false;
    await tracking.stopTracking();
    tracking.dispose();
  }
}

class RideLocationScope extends InheritedWidget {
  const RideLocationScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final RideLocationController controller;

  static RideLocationController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RideLocationScope>();
    assert(scope != null, 'RideLocationScope not found');
    return scope!.controller;
  }

  static RideLocationController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RideLocationScope>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(RideLocationScope oldWidget) =>
      controller != oldWidget.controller;
}
