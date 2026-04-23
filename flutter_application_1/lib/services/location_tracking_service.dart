import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'supabase_client.dart';

/// Streams GPS during an active rental and writes to Supabase (last-known + history).
/// For background updates, iOS needs UIBackgroundModes location; Android may show a
/// system notification when the app is backgrounded (OS / Play Services behavior).
class LocationTrackingService {
  StreamSubscription<Position>? _sub;
  DateTime? _lastWriteAt;

  /// Requests when-in-use then always (best effort) for background-capable tracking.
  Future<void> ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Location services are disabled.');
    }

    var whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) {
      throw StateError('Location permission denied.');
    }

    final always = await Permission.locationAlways.request();
    if (!always.isGranted && defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS may still allow limited updates; continue but admin may see stale points.
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Geolocator permission not available.');
    }
  }

  LocationSettings _locationSettings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
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
    await ensurePermissions();

    _sub = Geolocator.getPositionStream(
      locationSettings: _locationSettings(),
    ).listen((pos) async {
      final now = DateTime.now();
      final last = _lastWriteAt;
      if (last != null && now.difference(last) < minInterval) return;
      _lastWriteAt = now;

      final payload = {
        'rental_id': rentalId,
        'user_id': user.id,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy_m': pos.accuracy,
        'recorded_at': now.toIso8601String(),
      };

      try {
        await SupabaseClientProvider.client.from('rental_last_location').upsert(
              payload,
              onConflict: 'rental_id',
            );

        await SupabaseClientProvider.client.from('rental_locations').insert(payload);
      } catch (_) {
        // Avoid crashing the stream; next fix will surface in logs.
      }
    });
  }

  Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
    _lastWriteAt = null;
  }
}
