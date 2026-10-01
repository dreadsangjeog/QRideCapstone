import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, ValueNotifier;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_compass.dart';
import 'supabase_client.dart';

/// Streams GPS + compass during an active rental and writes to Supabase
/// (`rental_last_location` upsert + `rental_locations` history insert).
///
/// On Android the rental foreground task is the only ongoing GPS client and
/// the only ongoing admin-map writer. It keeps a GPS listener open for the
/// whole ride, including when QRide is backgrounded or the phone is locked
/// in a pocket. This service mirrors those fixes into the rider UI and
/// forwards compass heading. When a rental is first approved it also writes
/// the phone's last known point once, so the admin pin does not wait on a
/// satellite cold start. Opening a second Geolocator stream made the admin
/// pin flicker red/yellow and stop when the screen locked.
///
/// On iOS this service is the writer. Server uploads are throttled to about
/// every 3 seconds.
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
  bool _mirrorOnly = false;
  void Function(double heading)? _headingListener;

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
  static const Duration _writeTimeout = Duration(seconds: 12);
  static const Duration _streamStall = Duration(seconds: 12);

  /// True while an active rental is being tracked in this isolate.
  bool get isTracking => _rentalId != null;

  /// Android: UI is mirroring the foreground-task writer and must not open GPS.
  bool get isMirroring => _mirrorOnly && _rentalId != null;

  /// True when the GPS stream/poll/heartbeat are actively listening.
  bool get isStreamActive => _rentalId != null && (_sub != null || _mirrorOnly);

  /// Ensures location service is on and permission is granted.
  Future<void> ensurePermissions() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError(
        'Location services are turned off. Please enable GPS and try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError(
        'Location permission denied. Please allow location access for QRide.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError(
        'Location permission permanently denied. Enable it in app Settings.',
      );
    }

    // Android 13+: Geolocator FGS shows an ongoing notification.
    final notify = await Permission.notification.status;
    if (notify.isDenied) {
      await Permission.notification.request();
    }
  }

  /// iOS: flush the last fix when the screen locks. Android uploads continue
  /// in the foreground-task isolate, so this is not used there.
  Future<void> keepSharingWithScreenOff() async {
    if (_rentalId == null) return;
    final pos = _lastPosition;
    if (pos != null) unawaited(_attemptWrite(pos, force: true));
  }

  /// App visible again. Only rebuild the stream if it died; otherwise flush.
  Future<void> resumeFromBackground() async {
    if (_rentalId == null || _mirrorOnly) return;

    if (_sub == null) {
      _listenStream(forceAndroidManager: _useLegacyAndroidManager);
      _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) {
        final last = _lastGpsAt;
        if (last == null) return;
        if (DateTime.now().difference(last) > _streamStall) {
          unawaited(_restartStream());
        }
      });
      _heartbeat ??= Timer.periodic(_minInterval, (_) {
        final pos = _lastPosition;
        if (pos != null) unawaited(_attemptWrite(pos, force: true));
      });
    } else {
      // Stream still alive — restart only if GPS has gone quiet.
      final last = _lastGpsAt;
      if (last == null || DateTime.now().difference(last) > _streamStall) {
        await _restartStream();
      }
    }

    final pos = _lastPosition;
    if (pos != null) unawaited(_attemptWrite(pos, force: true));
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
    // Fallback only. The normal Android path does not open this stream.
    // If it does start, it is the only location client (no second FGS).
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        forceLocationManager: forceAndroidManager,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              'Sharing bike location. Stays on if you leave QRide or lock the phone.',
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
    _sub =
        Geolocator.getPositionStream(
          locationSettings: _locationSettings(
            forceAndroidManager: forceAndroidManager,
          ),
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

  /// Writes the phone's last known point once so the admin pin appears as
  /// soon as a rental is approved.
  ///
  /// The rental GPS listener often needs half a minute for its first
  /// satellite fix. This does not open a location stream.
  Future<void> seedAdminFromLastKnown(String rentalId) async {
    final userId = SupabaseClientProvider.client.auth.currentUser?.id;
    if (userId == null) return;
    Position? pos;
    try {
      pos = await Geolocator.getLastKnownPosition();
    } catch (e) {
      // ignore: avoid_print
      print('[LocationTracking] seed read failed: $e');
      return;
    }
    if (pos == null) return;
    final age = DateTime.now().difference(pos.timestamp);
    if (!age.isNegative && age > const Duration(minutes: 10)) return;

    final payload = <String, dynamic>{
      'rental_id': rentalId,
      'user_id': userId,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy_m': pos.accuracy,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };
    final heading = _usableHeading(pos);
    if (heading != null) payload['heading'] = heading;
    try {
      await SupabaseClientProvider.client
          .from('rental_last_location')
          .upsert(payload, onConflict: 'rental_id')
          .timeout(_writeTimeout);
      // ignore: avoid_print
      print(
        '[LocationTracking] seed OK lat=${pos.latitude.toStringAsFixed(5)} '
        'lng=${pos.longitude.toStringAsFixed(5)}',
      );
    } catch (e) {
      if (!payload.containsKey('heading')) {
        // ignore: avoid_print
        print('[LocationTracking] seed failed: $e');
        return;
      }
      payload.remove('heading');
      try {
        await SupabaseClientProvider.client
            .from('rental_last_location')
            .upsert(payload, onConflict: 'rental_id')
            .timeout(_writeTimeout);
      } catch (e2) {
        // ignore: avoid_print
        print('[LocationTracking] seed failed: $e2');
      }
    }
  }

  /// Rider UI mirror of the Android foreground-task writer.
  ///
  /// Does not open Geolocator. Compass heading is forwarded so the admin pin
  /// can still turn while the bike is standing still.
  Future<void> startMirror({
    required String rentalId,
    void Function(double heading)? onHeading,
  }) async {
    if (_mirrorOnly && _rentalId == rentalId) {
      _headingListener = onHeading;
      return;
    }
    await stopTracking();
    _rentalId = rentalId;
    _mirrorOnly = true;
    _headingListener = onHeading;
    _startCompass();
  }

  /// Applies a fix already uploaded by the foreground task.
  void applyExternalFix({
    required double latitude,
    required double longitude,
    required double accuracy,
    double? heading,
    required DateTime writtenAt,
  }) {
    if (_rentalId == null) return;
    final pos = Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: writtenAt,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading ?? _compassHeading ?? 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    _lastPosition = pos;
    _lastGpsAt = writtenAt;
    position.value = pos;
    lastWriteAt.value = writtenAt;
    lastError.value = null;
    if (_compassHeading == null && heading != null) {
      _publishHeading(heading);
    }
  }

  Future<void> _pollOnce() async {
    if (_rentalId == null || _mirrorOnly) return;
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
    if (_rentalId == null || _mirrorOnly || _restartingStream) return;
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
        print(
          '[LocationTracking] drop outlier jump ${jumped.toStringAsFixed(0)}m',
        );
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
    _headingListener?.call(h);
  }

  Future<void> _attemptWrite(Position pos, {bool force = false}) async {
    if (_mirrorOnly) return;
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
      // Always UTC with Z so the admin map does not mis-read local time.
      'recorded_at': now.toUtc().toIso8601String(),
    };

    try {
      // 1) Upsert drives the admin map — this must finish before we release
      //    the write lock. History must not block it.
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

      _lastSuccessAt = now;
      lastWriteAt.value = now;
      lastError.value = null;
      // ignore: avoid_print
      print(
        '[LocationTracking] write OK lat=${pos.latitude.toStringAsFixed(5)} '
        'lng=${pos.longitude.toStringAsFixed(5)} '
        'hdg=${headingDeg?.toStringAsFixed(0) ?? '-'}',
      );

      // 2) History trail — fire-and-forget so a slow insert cannot stall
      //    the next admin upsert (especially with the screen locked).
      unawaited(_insertHistory(Map<String, dynamic>.from(payload)));
    } on TimeoutException {
      lastError.value =
          'Network timeout while sharing location. Check rider\'s internet.';
      // ignore: avoid_print
      print(
        '[LocationTracking] write TIMEOUT after ${_writeTimeout.inSeconds}s',
      );
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

  Future<void> _insertHistory(Map<String, dynamic> payload) async {
    try {
      await SupabaseClientProvider.client
          .from('rental_locations')
          .insert(payload)
          .timeout(_writeTimeout);
    } catch (e) {
      // ignore: avoid_print
      print('[LocationTracking] history insert failed (non-fatal): $e');
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
    _mirrorOnly = false;
    _headingListener = null;
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
    _watchdog?.cancel();
    position.dispose();
    heading.dispose();
    lastWriteAt.dispose();
    lastError.dispose();
  }
}
