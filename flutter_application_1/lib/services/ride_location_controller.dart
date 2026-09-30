import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_tracking_service.dart';
import 'rental_repository.dart';
import 'supabase_client.dart';

/// Keeps rental GPS → admin uploads alive for the whole ride.
///
/// Single writer: [LocationTrackingService] with Geolocator’s Android
/// foreground notification. That is the path that already works while QRide
/// is open, and it must stay running when the rider opens another app or
/// locks the screen (while-using + location FGS — not “Allow all the time”).
///
/// A second location foreground service was previously started on background;
/// that competed for GPS and is why admin went “Update delayed” outside QRide.
class RideLocationController with WidgetsBindingObserver {
  RideLocationController({
    RentalRepository? repo,
    LocationTrackingService? tracking,
  }) : _repo = repo ?? RentalRepository(),
       tracking = tracking ?? LocationTrackingService();

  final RentalRepository _repo;
  final LocationTrackingService tracking;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  Timer? _poll;
  String? _rentalId;
  bool _started = false;
  bool _syncing = false;
  bool _syncQueued = false;

  String? get rentalId => _rentalId;
  bool get isSharing => _rentalId != null;

  static const _shareEvery = Duration(seconds: 3);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _authSub = SupabaseClientProvider.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.signedOut) {
          unawaited(_clearAll());
          return;
        }
        // Token refresh must not restart GPS.
        if (data.event == AuthChangeEvent.tokenRefreshed) return;
        if (data.session != null) unawaited(_sync());
      },
    );
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
        unawaited(_onResumed());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Do not tear down Geolocator FGS — flush only.
        unawaited(tracking.keepSharingWithScreenOff());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _onResumed() async {
    await _sync();
    await tracking.resumeFromBackground();
  }

  Future<void> _sync() async {
    if (_syncing) {
      _syncQueued = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncQueued = false;
        await _syncOnce();
      } while (_syncQueued && _started);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    try {
      final rental = await _repo.fetchMyActiveRental();
      if (rental != null && rental.isActive) {
        // Same rental already tracking — leave the GPS stack alone.
        if (_rentalId == rental.id && tracking.isTracking) {
          if (!tracking.isStreamActive) {
            await tracking.resumeFromBackground();
          }
          return;
        }
        _rentalId = rental.id;
        await tracking.startTracking(
          rentalId: rental.id,
          minInterval: _shareEvery,
        );
        return;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RideLocation] sync failed: $e');
      // Keep existing tracking on transient network errors.
      return;
    }

    if (_rentalId == null) return;
    await _clearAll();
  }

  Future<void> _clearAll() async {
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
    await _authSub?.cancel();
    _authSub = null;
    _poll?.cancel();
    _poll = null;
    await _channel?.unsubscribe();
    _channel = null;
    _started = false;
    await _clearAll();
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
