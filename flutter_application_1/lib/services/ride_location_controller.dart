import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_tracking_service.dart';
import 'rental_repository.dart';
import 'ride_foreground_task.dart';
import 'supabase_client.dart';

/// Keeps rental GPS → admin uploads alive for the whole ride.
///
/// Android uses one writer: [RideForegroundTask]. The service starts when the
/// rider requests a bike, while the app is open, and then stays up if they
/// leave or close QRide. It does not read GPS until staff approve. After
/// approval its isolate keeps a GPS listener registered and uploads while
/// QRide is open, in another app, closed from the recent-apps list, or with
/// the screen locked in a pocket. The UI [LocationTrackingService] only
/// mirrors those fixes.
///
/// A second Geolocator stream beside that task stalled uploads (admin pin
/// flickering red/yellow) and then stopped entirely once the UI isolate was
/// frozen with the screen off.
///
/// iOS keeps writing from [LocationTrackingService] with background location.
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
  String? _watchId;
  bool _started = false;
  bool _syncing = false;
  bool _syncQueued = false;

  String? get rentalId => _rentalId;
  bool get isSharing => _rentalId != null;

  static const _shareEvery = Duration(seconds: 3);

  bool get _usesForegroundWriter =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (_usesForegroundWriter) {
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
        // Refresh the task's token without tearing down GPS.
        if (data.event == AuthChangeEvent.tokenRefreshed) {
          unawaited(_pushAuthToForeground());
          return;
        }
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
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResumed());
      return;
    }
    if (state == AppLifecycleState.detached) return;
    // Android uploads continue in the foreground-task isolate.
    if (!_usesForegroundWriter) {
      unawaited(tracking.keepSharingWithScreenOff());
    }
  }

  void _onFgTaskData(Object data) {
    if (data is! Map) return;
    if (data['stopped'] == true) {
      unawaited(_sync());
      return;
    }
    final lat = data['lat'];
    final lng = data['lng'];
    if (lat is! num || lng is! num) return;
    final acc = data['accuracy_m'];
    final heading = data['heading'];
    final atRaw = data['at']?.toString();
    final at = atRaw == null
        ? DateTime.now().toUtc()
        : (DateTime.tryParse(atRaw) ?? DateTime.now().toUtc());
    tracking.applyExternalFix(
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      accuracy: acc is num ? acc.toDouble() : 0,
      heading: heading is num ? heading.toDouble() : null,
      writtenAt: at,
    );
  }

  void _sendHeading(double heading) {
    RideForegroundTask.pushHeading(heading);
  }

  Future<void> _onResumed() async {
    await _sync();
    if (!_usesForegroundWriter) {
      await tracking.resumeFromBackground();
    }
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
      if (rental != null && rental.isPending && _usesForegroundWriter) {
        if (tracking.isTracking || tracking.isMirroring) {
          await tracking.stopTracking();
        }
        _rentalId = null;
        final waiting = await _ensureWaitingWriter(rental.id);
        if (waiting) _watchId = rental.id;
        return;
      }
      if (rental != null && rental.isActive) {
        // The map already has a point. Write it now so staff see the pin
        // without waiting for the rental GPS listener's first satellite fix.
        if (_rentalId != rental.id) {
          unawaited(tracking.seedAdminFromLastKnown(rental.id));
        }
        if (_usesForegroundWriter) {
          try {
            // Drop any UI Geolocator stream before the task isolate reads GPS.
            if (!tracking.isMirroring) {
              await tracking.ensurePermissions();
              await tracking.startMirror(
                rentalId: rental.id,
                onHeading: _sendHeading,
              );
            }
            final running = await _ensureForegroundWriter(rental.id);
            if (running) {
              _rentalId = rental.id;
              _watchId = rental.id;
              return;
            }
          } catch (e) {
            // ignore: avoid_print
            print('[RideLocation] foreground writer failed: $e');
          }
          if (tracking.isMirroring) await tracking.stopTracking();
        }

        // iOS, or Android if the foreground task could not start.
        if (_rentalId == rental.id &&
            tracking.isTracking &&
            !tracking.isMirroring) {
          if (!tracking.isStreamActive) {
            await tracking.resumeFromBackground();
          }
          return;
        }
        _rentalId = rental.id;
        _watchId = rental.id;
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

    if (_rentalId == null && _watchId == null) return;
    await _clearAll();
  }

  /// Starts the Android writer while the UI is allowed to start a foreground
  /// service. Returns false when it is not running so the caller can fall back.
  Future<bool> _ensureForegroundWriter(String rentalId) async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    final session = SupabaseClientProvider.client.auth.currentSession;
    if (user == null || session == null) return false;
    try {
      await RideForegroundTask.ensureRunning(
        rentalId: rentalId,
        userId: user.id,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      return await RideForegroundTask.isRunning;
    } catch (e) {
      // ignore: avoid_print
      print('[RideLocation] foreground writer failed: $e');
      return await RideForegroundTask.isRunning;
    }
  }

  Future<bool> _ensureWaitingWriter(String rentalId) async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    final session = SupabaseClientProvider.client.auth.currentSession;
    if (user == null || session == null) return false;
    try {
      await RideForegroundTask.ensureWaiting(
        rentalId: rentalId,
        userId: user.id,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
      return await RideForegroundTask.isRunning;
    } catch (e) {
      // ignore: avoid_print
      print('[RideLocation] waiting writer failed: $e');
      return await RideForegroundTask.isRunning;
    }
  }

  Future<void> _pushAuthToForeground() async {
    final rentalId = _rentalId ?? _watchId;
    if (!_usesForegroundWriter || rentalId == null) return;
    if (_rentalId != null) {
      await _ensureForegroundWriter(rentalId);
      return;
    }
    await _ensureWaitingWriter(rentalId);
  }

  Future<void> _clearAll() async {
    _rentalId = null;
    _watchId = null;
    await tracking.stopTracking();
    if (_usesForegroundWriter) await RideForegroundTask.stop();
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
    if (_usesForegroundWriter) {
      FlutterForegroundTask.removeTaskDataCallback(_onFgTaskData);
    }
    await _authSub?.cancel();
    _authSub = null;
    _poll?.cancel();
    _poll = null;
    await _channel?.unsubscribe();
    _channel = null;
    _started = false;
    final signedIn =
        SupabaseClientProvider.client.auth.currentUser != null;
    var keepService = false;
    if (_usesForegroundWriter && signedIn) {
      keepService = _rentalId != null ||
          _watchId != null ||
          await RideForegroundTask.isRunning;
    }
    // Swiping QRide away disposes this widget. Leave the rental service
    // running so a pending request can notice approval, and an active ride
    // keeps sharing, without the rider opening the app again.
    if (!keepService) await _clearAll();
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
