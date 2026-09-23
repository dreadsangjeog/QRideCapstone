import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, ValueNotifier;
import 'package:geolocator/geolocator.dart';

import 'device_compass.dart';
import 'supabase_client.dart';

/// Streams GPS + compass during an active rental and writes to Supabase
/// (`rental_last_location` upsert + `rental_locations` history insert).
///
/// The rider map updates as soon as GPS reports movement. Uploads to the
/// server (admin map) are throttled to about every 3 seconds to save battery
/// and data.
///
/// GPS bearing only updates while moving. Phone rotation while standing still
/// comes from the device compass so the admin map pin can turn in place.
///
/// Some Android devices stop the fused location stream after the first fix.
/// A poll + stream-restart watchdog keeps the pin moving for the whole ride.
class LocationTrackingService {
  StreamSubscription<Position>? _sub;
  StreamSubscription<CompassReading>? _compassSub;
  Timer? _heartbeat;
  Timer? _pollTimer;
  Timer? _watchdog;

  /// Throttle is **post-success**: after a successful write, block writes for
  /// [minInterval]. Failures never set this, so retries happen on the next fix.
  DateTime? _lastSuccessAt;
  DateTime? _lastGpsAt;
  bool _writing = false;
  bool _restartingStream = false;
  bool _useLegacyAndroidManager = false;
  String? _rentalId;
  String? _userId;
  Duration _minInterval = const Duration(seconds: 3);
  double? _lastGoodHeading;
  double? _compassHeading;
  Position? _lastPosition;
  Position? _pendingWrite;
  bool _pendingForce = false;

  /// Most recent position from the GPS stream / poll.
  final ValueNotifier<Position?> position = ValueNotifier<Position?>(null);

  /// Facing direction in degrees (0–360, north = 0). Compass preferred.
  final ValueNotifier<double?> heading = ValueNotifier<double?>(null);

  /// Timestamp of the most recent successful Supabase write.
  final ValueNotifier<DateTime?> lastWriteAt = ValueNotifier<DateTime?>(null);

  /// Last error from either GPS, the network, or RLS.
  /// Cleared on the next successful write.
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  /// Hard timeout per Supabase REST call. If the network or PostgREST hangs,
  /// the call is aborted and surfaced as an error.
  static const Duration _writeTimeout = Duration(seconds: 8);
  static const Duration _streamStall = Duration(seconds: 10);
  /// Backup GPS poll. Network uploads are throttled separately via [minInterval].
  static const Duration _pollEvery = Duration(seconds: 3);

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

  LocationSettings _locationSettings({bool forceAndroidManager = false}) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        allowBackgroundLocationUpdates: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    // Stream stays frequent so the rider map moves as soon as GPS reports
    // movement. Uploads to Supabase are throttled by [_minInterval] (~3s).
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: forceAndroidManager,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'QRide is tracking your ride location.',
          notificationTitle: 'Rental in progress',
          enableWakeLock: true,
          setOngoing: true,
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

    _startCompass();
    await _seedFirstFix();
    _listenStream(forceAndroidManager: false);
    _startPoll();
    _startWatchdog();

    // Heartbeat keeps server "last seen" fresh even if GPS is quiet.
    _heartbeat = Timer.periodic(_minInterval, (_) {
      final pos = _lastPosition;
      if (pos != null) unawaited(_attemptWrite(pos, force: true));
    });
  }

  Future<void> _seedFirstFix() async {
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _ingest(first, source: 'seed');
      unawaited(_attemptWrite(first, force: true));
    } catch (_) {
      /* stream / poll will produce a fix shortly */
    }
  }

  void _listenStream({required bool forceAndroidManager}) {
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(
      locationSettings:
          _locationSettings(forceAndroidManager: forceAndroidManager),
    ).listen(
      (pos) => _ingest(pos, source: 'stream'),
      onError: (Object e) {
        lastError.value = 'GPS error: $e';
        // ignore: avoid_print
        print('[LocationTracking] stream error: $e');
        unawaited(_restartStream());
      },
      onDone: () {
        // ignore: avoid_print
        print('[LocationTracking] stream done — restarting');
        unawaited(_restartStream());
      },
    );
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollEvery, (_) => unawaited(_pollOnce()));
  }

  Future<void> _pollOnce() async {
    if (_rentalId == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _ingest(pos, source: 'poll');
    } catch (e) {
      // ignore: avoid_print
      print('[LocationTracking] poll failed: $e');
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      final last = _lastGpsAt;
      if (last == null) return;
      if (DateTime.now().difference(last) > _streamStall) {
        unawaited(_restartStream());
      }
    });
  }

  Future<void> _restartStream() async {
    if (_rentalId == null || _restartingStream) return;
    _restartingStream = true;
    try {
      // Alternate fused vs legacy manager — some OEMs stall on one path.
      if (defaultTargetPlatform == TargetPlatform.android) {
        _useLegacyAndroidManager = !_useLegacyAndroidManager;
      }
      // ignore: avoid_print
      print(
        '[LocationTracking] restarting GPS stream '
        '(legacyManager=$_useLegacyAndroidManager)',
      );
      _listenStream(forceAndroidManager: _useLegacyAndroidManager);
      await _pollOnce();
    } finally {
      _restartingStream = false;
    }
  }

  void _ingest(Position pos, {required String source}) {
    final prev = _lastPosition;
    // Ignore absurd jumps (>2km in one step) after we already have a fix —
    // those are usually bad cold-start / cached outliers.
    if (prev != null) {
      final jumped = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        pos.latitude,
        pos.longitude,
      );
      if (jumped > 2000 && pos.accuracy > 80) {
        // ignore: avoid_print
        print('[LocationTracking] drop outlier jump ${jumped.toStringAsFixed(0)}m');
        return;
      }
    }

    _lastGpsAt = DateTime.now();
    _lastPosition = pos;
    position.value = pos;
    _publishHeading(_usableHeading(pos));
    unawaited(_attemptWrite(pos));

    // ignore: avoid_print
    print(
      '[LocationTracking] $source '
      'lat=${pos.latitude.toStringAsFixed(5)} '
      'lng=${pos.longitude.toStringAsFixed(5)} '
      'acc=${pos.accuracy.toStringAsFixed(0)}m',
    );
  }

  void _startCompass() {
    try {
      final stream = DeviceCompass.events;
      if (stream == null) return;
      _compassSub = stream.listen((event) {
        final h = event.heading;
        if (h == null || h.isNaN) return;
        var deg = h % 360;
        if (deg < 0) deg += 360;
        _compassHeading = deg;
        _lastGoodHeading = deg;
        _publishHeading(deg);
      });
    } catch (e) {
      // ignore: avoid_print
      print('[LocationTracking] compass unavailable: $e');
    }
  }

  void _publishHeading(double? h) {
    if (h == null) return;
    final prev = heading.value;
    if (prev != null && (prev - h).abs() < 1.5) return;
    heading.value = h;
  }

  Future<void> _attemptWrite(Position pos, {bool force = false}) async {
    final rentalId = _rentalId;
    final userId = _userId;
    if (rentalId == null || userId == null) return;

    // One write at a time — keep the newest fix queued so movement is not lost.
    if (_writing) {
      _pendingWrite = pos;
      _pendingForce = _pendingForce || force;
      return;
    }

    // Throttle ONLY after a successful write. Failures retry on next fix.
    final last = _lastSuccessAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minInterval) {
      _pendingWrite = pos;
      return;
    }

    // Skip absurdly bad fixes (>500m), but never on first write.
    if (_lastSuccessAt != null && pos.accuracy > 500) return;

    _writing = true;
    final now = DateTime.now();
    final headingDeg = _usableHeading(pos);
    final payload = <String, dynamic>{
      'rental_id': rentalId,
      'user_id': userId,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy_m': pos.accuracy,
      'heading': headingDeg,
      'recorded_at': now.toUtc().toIso8601String(),
    };

    try {
      // 1) Upsert last-known location (drives admin map).
      try {
        await SupabaseClientProvider.client
            .from('rental_last_location')
            .upsert(payload, onConflict: 'rental_id')
            .timeout(_writeTimeout);
      } catch (e) {
        if (payload.containsKey('heading')) {
          payload.remove('heading');
          await SupabaseClientProvider.client
              .from('rental_last_location')
              .upsert(payload, onConflict: 'rental_id')
              .timeout(_writeTimeout);
        } else {
          rethrow;
        }
      }

      // 2) Insert history row (best effort).
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
          'lng=${pos.longitude.toStringAsFixed(5)} '
          'hdg=${headingDeg?.toStringAsFixed(0) ?? '-'}');
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
      final pending = _pendingWrite;
      final pendingForce = _pendingForce;
      _pendingWrite = null;
      _pendingForce = false;
      if (pending != null && _rentalId != null) {
        unawaited(_attemptWrite(pending, force: pendingForce));
      }
    }
  }

  String _humanizeError(Object e) {
    final s = e.toString();
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

  /// Prefer compass (works while standing still). Fall back to GPS bearing.
  double? _usableHeading(Position pos) {
    final compass = _compassHeading;
    if (compass != null && compass >= 0 && compass <= 360) {
      _lastGoodHeading = compass;
      return compass;
    }

    final h = pos.heading;
    if (h.isNaN || h < 0 || h > 360) return _lastGoodHeading;
    final acc = pos.headingAccuracy;
    if (acc.isFinite && acc > 45 && _lastGoodHeading != null) {
      return _lastGoodHeading;
    }
    _lastGoodHeading = h;
    return h;
  }

  Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
    await _compassSub?.cancel();
    _compassSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _watchdog?.cancel();
    _watchdog = null;
    _writing = false;
    _restartingStream = false;
    _useLegacyAndroidManager = false;
    _lastSuccessAt = null;
    _lastGpsAt = null;
    _lastGoodHeading = null;
    _compassHeading = null;
    _lastPosition = null;
    _pendingWrite = null;
    _pendingForce = false;
    _rentalId = null;
    _userId = null;
    position.value = null;
    heading.value = null;
    lastWriteAt.value = null;
    lastError.value = null;
  }

  void dispose() {
    _sub?.cancel();
    _compassSub?.cancel();
    _heartbeat?.cancel();
    _pollTimer?.cancel();
    _watchdog?.cancel();
    position.dispose();
    heading.dispose();
    lastWriteAt.dispose();
    lastError.dispose();
  }
}
