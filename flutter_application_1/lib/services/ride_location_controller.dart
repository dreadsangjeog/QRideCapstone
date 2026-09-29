import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_tracking_service.dart';
import 'rental_repository.dart';
import 'ride_foreground_task.dart';
import 'supabase_client.dart';

/// Orchestrates GPS for an active rental.
///
/// - [LocationTrackingService]: rider UI + foreground Supabase writes while
///   QRide is open (no second Android notification).
/// - [RideForegroundTask]: durable ~3s admin-map uploads with screen locked or
///   another app open (owns the “Rental in progress” notice).
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
  String? _fgRentalId;
  bool _started = false;
  bool _fgRunning = false;
  bool _syncing = false;
  bool _syncQueued = false;

  String? get rentalId => _rentalId;
  bool get isSharing => _rentalId != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!kIsWeb) {
      RideForegroundTask.init();
      FlutterForegroundTask.addTaskDataCallback(_onFgTaskData);
    }
    WidgetsBinding.instance.addObserver(this);
    _authSub = SupabaseClientProvider.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.signedOut) {
          unawaited(_clearAll());
          return;
        }
        // Token refresh or sign-in — re-check rental + refresh FG auth.
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
        unawaited(_sync());
        unawaited(tracking.resumeFromBackground());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(tracking.keepSharingWithScreenOff());
        unawaited(_ensureFgTask());
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onFgTaskData(Object data) {
    if (data is! Map) return;
    if (data['stopped'] == true) {
      _fgRunning = false;
      _fgRentalId = null;
      unawaited(_sync());
      return;
    }
    tracking.noteExternalWrite(
      heading: (data['heading'] as num?)?.toDouble(),
    );
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
    RentalSnapshot? snap;
    try {
      final rental = await _repo.fetchMyActiveRental();
      if (rental != null && rental.isActive) {
        snap = RentalSnapshot(id: rental.id);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RideLocation] sync failed: $e');
      // Keep existing tracking if a transient network error hit.
      return;
    }

    if (snap != null) {
      final same = _rentalId == snap.id;
      _rentalId = snap.id;
      if (!same || !tracking.isTracking) {
        try {
          await tracking.startTracking(
            rentalId: snap.id,
            minInterval: RideForegroundTask.shareEvery,
          );
        } catch (e) {
          // UI stream failed (permission etc.) — still start FG uploads.
          // ignore: avoid_print
          print('[RideLocation] UI tracking failed: $e');
        }
      }
      await _ensureFgTask();
      return;
    }

    if (_rentalId == null && !_fgRunning) return;
    await _clearAll();
  }

  Future<void> _ensureFgTask() async {
    if (kIsWeb) return;
    final rentalId = _rentalId;
    final user = SupabaseClientProvider.client.auth.currentUser;
    final session = SupabaseClientProvider.client.auth.currentSession;
    if (rentalId == null || user == null || session == null) return;

    try {
      final running = await RideForegroundTask.isRunning;
      if (!running) _fgRunning = false;
      final rentalChanged = _fgRentalId != rentalId;

      if (running && !rentalChanged) {
        await RideForegroundTask.ensureRunning(
          rentalId: rentalId,
          userId: user.id,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        );
        _fgRunning = true;
        _fgRentalId = rentalId;
        return;
      }

      await RideForegroundTask.start(
        rentalId: rentalId,
        userId: user.id,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      _fgRunning = true;
      _fgRentalId = rentalId;
    } catch (e) {
      // ignore: avoid_print
      print('[RideLocation] foreground task start failed: $e');
      _fgRunning = false;
      _fgRentalId = null;
    }
  }

  Future<void> _stopFgTask() async {
    if (kIsWeb) return;
    await RideForegroundTask.stop();
    _fgRunning = false;
    _fgRentalId = null;
  }

  Future<void> _clearAll() async {
    _rentalId = null;
    await tracking.stopTracking();
    await _stopFgTask();
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
    if (!kIsWeb) {
      FlutterForegroundTask.removeTaskDataCallback(_onFgTaskData);
    }
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

class RentalSnapshot {
  const RentalSnapshot({required this.id});
  final String id;
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
