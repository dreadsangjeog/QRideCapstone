import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, ValueNotifier;
import 'package:geolocator/geolocator.dart';

import 'supabase_client.dart';

/// Streams GPS during an active rental and writes to Supabase
/// (`rental_last_location` upsert + `rental_locations` history insert).
///
/// Exposes [position], [lastWriteAt], and [lastError] as listenable
/// notifiers so the UI can show live feedback (map dot, "shared 5s ago",
/// or any GPS / RLS errors).
class LocationTrackingService {
  StreamSubscription<Position>? _sub;

  /// Throttle is **post-success**: after a successful write, block writes for
  /// [minInterval]. Failures never set this, so retries happen on the next fix.
  DateTime? _lastSuccessAt;
  bool _writing = false;
  String? _rentalId;
  String? _userId;
  Duration _minInterval = const Duration(seconds: 15);

  /// Most recent position from the GPS stream.
  final ValueNotifier<Position?> position = ValueNotifier<Position?>(null);

  /// Timestamp of the most recent successful Supabase write.
  final ValueNotifier<DateTime?> lastWriteAt = ValueNotifier<DateTime?>(null);

  /// Last error from either GPS, the network, or RLS.
  /// Cleared on the next successful write.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// Hard timeout per Supabase REST call. If the network or PostgREST hangs,
  /// the call is aborted and surfaced as an error.
  static const Duration _writeTimeout = Duration(seconds: 8);

  /// Ensures location service is on and permission is granted.
  Future<void> ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError(
          'Location services are turned off. Please enable GPS and try again.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError(
          'Location permission denied. Please allow location access for QRide.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
          'Location permission permanently denied. Enable it in app Settings.');
    }
  }

  LocationSettings _locationSettings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'QRide is tracking your ride location.',
          notificationTitle: 'Rental in progress',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  Future<void> startTracking({
    required String rentalId,
    required Duration minInterval,
  }) async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    if (user == null) {
      throw StateError('User not signed in');
    }

    await stopTracking();
    try {
      await ensurePermissions();
    } catch (e) {
      lastError.value = e.toString().replaceFirst('Bad state: ', '');
      rethrow;
    }

    _rentalId = rentalId;
    _userId = user.id;
    _minInterval = minInterval;

    // ignore: avoid_print
    print('[LocationTracking] start rental=$rentalId user=${user.id}');

    // Push a quick first fix so the UI can centre instantly.
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      position.value = first;
      // Fire a write immediately for the first fix.
      unawaited(_attemptWrite(first));
    } catch (_) {/* stream will produce a fix shortly */}

    _sub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen(
      (pos) {
        position.value = pos;
        unawaited(_attemptWrite(pos));
      },
      onError: (Object e) {
        lastError.value = 'GPS error: $e';
        // ignore: avoid_print
        print('[LocationTracking] stream error: $e');
      },
    );
  }

  Future<void> _attemptWrite(Position pos) async {
    final rentalId = _rentalId;
    final userId = _userId;
    if (rentalId == null || userId == null) return;

    // One write at a time — drop concurrent overlaps.
    if (_writing) return;

    // Throttle ONLY after a successful write. Failures retry on next fix.
    final last = _lastSuccessAt;
    if (last != null &&
        DateTime.now().difference(last) < _minInterval) {
      return;
    }

    // Skip absurdly bad fixes (>500m), but never on first write.
    if (_lastSuccessAt != null && pos.accuracy > 500) return;

    _writing = true;
    final now = DateTime.now();
    final payload = {
      'rental_id': rentalId,
      'user_id': userId,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy_m': pos.accuracy,
      'recorded_at': now.toIso8601String(),
    };

    try {
      // 1) Upsert last-known location (drives admin map).
      await SupabaseClientProvider.client
          .from('rental_last_location')
          .upsert(payload, onConflict: 'rental_id')
          .timeout(_writeTimeout);

      // 2) Insert history row (best effort — don't fail the whole write if
      //    only the history row errors out).
      try {
        await SupabaseClientProvider.client
            .from('rental_locations')
            .insert(payload)
            .timeout(_writeTimeout);
      } catch (e) {
        // ignore: avoid_print
        print('[LocationTracking] history insert failed (non-fatal): $e');
      }

      _lastSuccessAt = now;
      lastWriteAt.value = now;
      lastError.value = null;
      // ignore: avoid_print
      print(
          '[LocationTracking] write OK lat=${pos.latitude.toStringAsFixed(5)} '
          'lng=${pos.longitude.toStringAsFixed(5)} acc=${pos.accuracy.toStringAsFixed(0)}m');
    } on TimeoutException {
      lastError.value =
          'Network timeout while sharing location. Check rider\'s internet.';
      // ignore: avoid_print
      print('[LocationTracking] write TIMEOUT after ${_writeTimeout.inSeconds}s');
    } catch (e) {
      lastError.value = _humanizeError(e);
      // ignore: avoid_print
      print('[LocationTracking] write FAILED: $e');
    } finally {
      _writing = false;
    }
  }

  String _humanizeError(Object e) {
    final s = e.toString();
    // Common Supabase / PostgREST error patterns surfaced as friendlier text.
    if (s.contains('PGRST') || s.contains('row-level security')) {
      return 'Server rejected location (RLS). Make sure rental is approved.';
    }
    if (s.contains('relation') && s.contains('does not exist')) {
      return 'Location tables missing. Run location_tables_setup.sql in Supabase.';
    }
    if (s.contains('JWT') || s.contains('expired')) {
      return 'Session expired. Sign out and sign back in.';
    }
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection on this device.';
    }
    return 'Could not save location: $s';
  }

  Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
    _writing = false;
    _lastSuccessAt = null;
    _rentalId = null;
    _userId = null;
    position.value = null;
    lastWriteAt.value = null;
    lastError.value = null;
  }

  void dispose() {
    _sub?.cancel();
    position.dispose();
    lastWriteAt.dispose();
    lastError.dispose();
  }
}
