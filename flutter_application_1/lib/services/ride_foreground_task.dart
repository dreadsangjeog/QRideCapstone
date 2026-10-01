import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../config/supabase_config.dart';
import 'device_compass.dart';
import 'ride_fix_gate.dart';
import 'ride_gps_events.dart';

/// Top-level entry used by [FlutterForegroundTask.startService].
@pragma('vm:entry-point')
void rideForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(RideLocationTaskHandler());
}

/// Sole Android GPS writer for an active rental.
///
/// The task isolate keeps a GPS listener registered and uploads fixes while
/// QRide is open, in another app, or with the screen locked in a pocket.
/// One-shot reads were returning a cached point (the compass still turned the
/// pin) and then stopping after a long screen lock.
///
/// The UI isolate must not also open a Geolocator stream — two location
/// clients stall the admin pin (red/yellow flicker).
class RideForegroundTask {
  RideForegroundTask._();

  static const _kRentalId = 'qride_rental_id';
  static const _kUserId = 'qride_user_id';
  static const _kAccessToken = 'qride_access_token';
  static const _kRefreshToken = 'qride_refresh_token';

  static const shareEvery = Duration(seconds: 3);

  static bool _initialized = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void init() {
    if (!_isAndroid || _initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'qride_rental_location',
        channelName: 'Rental location',
        channelDescription:
            'Shares bike location with staff while your ride is active.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          shareEvery.inMilliseconds,
        ),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  static Future<void> ensureNotificationPermission() async {
    if (!_isAndroid) return;
    final status = await FlutterForegroundTask.checkNotificationPermission();
    if (status != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    final ph = await Permission.notification.status;
    if (ph.isDenied) await Permission.notification.request();
  }

  static Future<void> start({
    required String rentalId,
    required String userId,
    required String accessToken,
    String? refreshToken,
  }) async {
    if (!_isAndroid) return;
    init();
    await ensureNotificationPermission();
    await _persistContext(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    if (await FlutterForegroundTask.isRunningService) {
      // Do not restart — that drops in-flight GPS writes. Just refresh context.
      pushContext(
        rentalId: rentalId,
        userId: userId,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 2601,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'Rental in progress',
      notificationText:
          'Sharing bike location. Stays on if you leave QRide or lock the phone.',
      callback: rideForegroundStartCallback,
    );
  }

  /// Keeps a running service on the current rental + fresh auth without a
  /// full restart when nothing changed.
  static Future<void> ensureRunning({
    required String rentalId,
    required String userId,
    required String accessToken,
    String? refreshToken,
  }) async {
    if (!_isAndroid) return;
    init();
    await _persistContext(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    pushContext(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    if (await FlutterForegroundTask.isRunningService) return;
    await start(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  static Future<void> stop() async {
    if (!_isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
    await FlutterForegroundTask.removeData(key: _kRentalId);
    await FlutterForegroundTask.removeData(key: _kUserId);
    await FlutterForegroundTask.removeData(key: _kAccessToken);
    await FlutterForegroundTask.removeData(key: _kRefreshToken);
  }

  static Future<bool> get isRunning async {
    if (!_isAndroid) return false;
    return FlutterForegroundTask.isRunningService;
  }

  static void pushContext({
    required String rentalId,
    required String userId,
    required String accessToken,
    String? refreshToken,
  }) {
    if (!_isAndroid) return;
    FlutterForegroundTask.sendDataToTask({
      'rental_id': rentalId,
      'user_id': userId,
      'access_token': accessToken,
      'refresh_token': ?refreshToken,
    });
  }

  /// Latest compass heading from the UI isolate (works while standing still).
  static void pushHeading(double heading) {
    if (!_isAndroid) return;
    if (heading.isNaN || heading < 0 || heading > 360) return;
    try {
      FlutterForegroundTask.sendDataToTask({'heading': heading});
    } catch (_) {}
  }

  static Future<void> _persistContext({
    required String rentalId,
    required String userId,
    required String accessToken,
    String? refreshToken,
  }) async {
    await FlutterForegroundTask.saveData(key: _kRentalId, value: rentalId);
    await FlutterForegroundTask.saveData(key: _kUserId, value: userId);
    await FlutterForegroundTask.saveData(key: _kAccessToken, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await FlutterForegroundTask.saveData(
        key: _kRefreshToken,
        value: refreshToken,
      );
    }
  }
}

class RideLocationTaskHandler extends TaskHandler {
  String? _accessToken;
  String? _refreshToken;
  String? _rentalId;
  String? _userId;
  bool _busy = false;
  bool _shareQueued = false;
  bool _useFusedFallback = false;
  int _listenGen = 0;
  Position? _lastPos;
  DateTime? _lastFixAt;
  DateTime? _lastUploadAt;
  DateTime? _lastRestartAt;
  double? _compassHeading;
  DateTime? _compassAt;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<CompassReading>? _compassSub;
  final RideFixGate _gate = RideFixGate();

  /// Consecutive 401/403 responses → rental ended or session dead; stop FGS.
  int _denyStreak = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadPersisted();
    _startCompass();
    await _listenGps();
    await _shareLatest();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_shareLatest());
    unawaited(_ensureGpsAlive());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _listenGen++;
    await _gpsSub?.cancel();
    _gpsSub = null;
    await _compassSub?.cancel();
    _compassSub = null;
  }

  @override
  void onReceiveData(Object data) {
    final map = _asStringKeyedMap(data);
    if (map == null) return;
    final rentalId = map['rental_id']?.toString();
    final userId = map['user_id']?.toString();
    final access = map['access_token']?.toString();
    final refresh = map['refresh_token']?.toString();
    if (rentalId != null && rentalId.isNotEmpty) _rentalId = rentalId;
    if (userId != null && userId.isNotEmpty) _userId = userId;
    if (access != null && access.isNotEmpty) _accessToken = access;
    if (refresh != null && refresh.isNotEmpty) _refreshToken = refresh;
    final rawHeading = map['heading'];
    if (rawHeading is num) {
      final h = rawHeading.toDouble();
      if (!h.isNaN && h >= 0 && h <= 360) {
        _compassHeading = h;
        _compassAt = DateTime.now();
      }
    }
  }

  Future<void> _loadPersisted() async {
    _rentalId = await FlutterForegroundTask.getData<String>(
      key: RideForegroundTask._kRentalId,
    );
    _userId = await FlutterForegroundTask.getData<String>(
      key: RideForegroundTask._kUserId,
    );
    _accessToken = await FlutterForegroundTask.getData<String>(
      key: RideForegroundTask._kAccessToken,
    );
    _refreshToken = await FlutterForegroundTask.getData<String>(
      key: RideForegroundTask._kRefreshToken,
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
        _compassAt = DateTime.now();
      });
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] compass unavailable: $e');
    }
  }

  /// One GPS subscription for the whole ride. Leaving it registered is what
  /// keeps fixes arriving after QRide is backgrounded or the screen locks.
  Future<void> _listenGps() async {
    final gen = ++_listenGen;
    await _gpsSub?.cancel();
    if (gen != _listenGen) return;
    _gpsSub = null;
    _lastRestartAt = DateTime.now();

    final stream = _useFusedFallback ? _fusedPositions() : RideGpsEvents.positions();
    _gpsSub = stream.listen(
      (pos) {
        if (gen != _listenGen) return;
        _onFix(pos);
      },
      onError: (Object e) {
        if (gen != _listenGen) return;
        // ignore: avoid_print
        print('[RideFgTask] gps stream error: $e');
        if (_useFusedFallback) return;
        _useFusedFallback = true;
        unawaited(_listenGps());
      },
      onDone: () {
        if (gen != _listenGen) return;
        // Let the watchdog re-subscribe. Restarting here loops if the
        // stream closes as soon as it opens.
      },
    );
  }

  Stream<Position> _fusedPositions() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 2),
      ),
    );
  }

  void _onFix(Position pos) {
    final now = DateTime.now().toUtc();
    final age = now.difference(pos.timestamp.toUtc());
    final fresh = age.isNegative || age <= const Duration(seconds: 20);
    final kept = _gate.accept(
      sampleTime: pos.timestamp,
      lat: pos.latitude,
      lng: pos.longitude,
      accuracy: pos.accuracy,
      now: now,
    );
    if (kept) _lastPos = pos;
    // Only a recent satellite time proves the chip is still running.
    // A cached point can be stored once, but it must not hold the pin green.
    if (fresh) _lastFixAt = DateTime.now();
    if (kept || fresh) unawaited(_shareLatest());
  }

  /// Re-subscribe if the chip goes quiet. A fused fallback that only repeats
  /// a cached point is abandoned so a long screen-off ride returns to GPS.
  Future<void> _ensureGpsAlive() async {
    final now = DateTime.now();
    final restarted = _lastRestartAt;
    // Before any fix, switch to the fused provider quickly. After that, keep
    // the longer cooldown so a quiet pocket ride is not restarted in a loop.
    final cooldown = _lastPos == null
        ? const Duration(seconds: 6)
        : const Duration(seconds: 30);
    if (restarted != null && now.difference(restarted) < cooldown) {
      return;
    }
    final fixAt = _lastFixAt;
    final quiet =
        fixAt == null || now.difference(fixAt) > const Duration(seconds: 18);
    if (!quiet && !_useFusedFallback) return;
    if (!quiet &&
        _useFusedFallback &&
        restarted != null &&
        now.difference(restarted) < const Duration(seconds: 60)) {
      return;
    }
    _useFusedFallback = quiet ? !_useFusedFallback : false;
    await _listenGps();
  }

  Future<void> _shareLatest() async {
    if (_busy) {
      _shareQueued = true;
      return;
    }
    if (_rentalId == null || _userId == null) await _loadPersisted();

    final rentalId = _rentalId;
    final userId = _userId;
    var token = _accessToken;
    if (rentalId == null || userId == null || token == null || token.isEmpty) {
      await _loadPersisted();
      return;
    }

    final pos = _lastPos;
    if (pos == null) return;
    final fixAt = _lastFixAt;
    final live = fixAt != null &&
        DateTime.now().difference(fixAt) <= const Duration(seconds: 45);
    // One cached seed is allowed. After that, only live GPS keeps sharing.
    if (!live && _lastUploadAt != null) return;

    final uploaded = _lastUploadAt;
    if (uploaded != null &&
        DateTime.now().difference(uploaded) < RideForegroundTask.shareEvery) {
      return;
    }

    _busy = true;
    try {
      final heading = _headingFor(pos);
      var result = await _upsertLocation(
        rentalId: rentalId,
        userId: userId,
        token: token,
        pos: pos,
        heading: heading,
      );

      if (result == _UpsertResult.unauthorized) {
        final refreshed = await _tryRefreshToken();
        if (refreshed != null) {
          _accessToken = refreshed;
          await FlutterForegroundTask.saveData(
            key: RideForegroundTask._kAccessToken,
            value: refreshed,
          );
          result = await _upsertLocation(
            rentalId: rentalId,
            userId: userId,
            token: refreshed,
            pos: pos,
            heading: heading,
          );
        }
      }

      if (result == _UpsertResult.ok) {
        _denyStreak = 0;
        _lastUploadAt = DateTime.now();
        // ignore: avoid_print
        print(
          '[RideFgTask] share ${pos.latitude.toStringAsFixed(5)},'
          '${pos.longitude.toStringAsFixed(5)} '
          'hdg=${heading?.toStringAsFixed(0) ?? '-'}',
        );
        FlutterForegroundTask.sendDataToMain({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy_m': pos.accuracy,
          'heading': heading,
          'at': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      }

      if (result == _UpsertResult.forbidden ||
          result == _UpsertResult.unauthorized) {
        _denyStreak++;
        if (_denyStreak >= 2) {
          // ignore: avoid_print
          print('[RideFgTask] stopping — rental ended or auth rejected');
          FlutterForegroundTask.sendDataToMain({
            'stopped': true,
            'reason': 'denied',
          });
          await FlutterForegroundTask.stopService();
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] share failed: $e');
    } finally {
      _busy = false;
      if (_shareQueued && _rentalId != null) {
        _shareQueued = false;
        unawaited(_shareLatest());
      }
    }
  }

  double? _headingFor(Position pos) {
    return chooseRideHeading(
      now: DateTime.now(),
      compass: _compassHeading,
      compassAt: _compassAt,
      speedMps: pos.speed,
      gpsHeading: pos.heading < 0 ? null : pos.heading,
    );
  }

  Future<_UpsertResult> _upsertLocation({
    required String rentalId,
    required String userId,
    required String token,
    required Position pos,
    double? heading,
  }) async {
    final base = SupabaseConfig.effectiveUrl;
    final anon = SupabaseConfig.effectiveAnonKey;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = <String, dynamic>{
      'rental_id': rentalId,
      'user_id': userId,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy_m': pos.accuracy,
      'recorded_at': now,
    };
    if (heading != null && !heading.isNaN && heading >= 0 && heading <= 360) {
      payload['heading'] = heading;
    }

    final headers = <String, String>{
      'apikey': anon,
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    };

    final upsertUri = Uri.parse(
      '$base/rest/v1/rental_last_location?on_conflict=rental_id',
    );

    Future<http.Response> post(Map<String, dynamic> body) {
      return http
          .post(upsertUri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
    }

    var upsert = await post(payload);
    if (upsert.statusCode == 401) return _UpsertResult.unauthorized;
    if (upsert.statusCode == 403) return _UpsertResult.forbidden;

    if (upsert.statusCode < 200 || upsert.statusCode >= 300) {
      if (!payload.containsKey('heading')) {
        // ignore: avoid_print
        print('[RideFgTask] upsert ${upsert.statusCode}: ${upsert.body}');
        return _UpsertResult.failed;
      }
      payload.remove('heading');
      upsert = await post(payload);
      if (upsert.statusCode == 401) return _UpsertResult.unauthorized;
      if (upsert.statusCode == 403) return _UpsertResult.forbidden;
      if (upsert.statusCode < 200 || upsert.statusCode >= 300) {
        // ignore: avoid_print
        print('[RideFgTask] upsert ${upsert.statusCode}: ${upsert.body}');
        return _UpsertResult.failed;
      }
    }

    // History must not hold `_busy` — a slow insert was skipping the next
    // admin upsert and the pin flipped to yellow.
    unawaited(_insertHistory(base: base, headers: headers, payload: payload));

    return _UpsertResult.ok;
  }

  Future<void> _insertHistory({
    required String base,
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$base/rest/v1/rental_locations'),
            headers: {...headers, 'Prefer': 'return=minimal'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {}
  }

  Future<String?> _tryRefreshToken() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return null;
    final base = SupabaseConfig.effectiveUrl;
    final anon = SupabaseConfig.effectiveAnonKey;
    try {
      final res = await http
          .post(
            Uri.parse('$base/auth/v1/token?grant_type=refresh_token'),
            headers: {
              'apikey': anon,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final access = body['access_token']?.toString();
      final nextRefresh = body['refresh_token']?.toString();
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        _refreshToken = nextRefresh;
        await FlutterForegroundTask.saveData(
          key: RideForegroundTask._kRefreshToken,
          value: nextRefresh,
        );
      }
      return access;
    } catch (_) {
      return null;
    }
  }
}

enum _UpsertResult { ok, unauthorized, forbidden, failed }

Map<String, dynamic>? _asStringKeyedMap(Object data) {
  if (data is Map<String, dynamic>) return data;
  if (data is! Map) return null;
  return <String, dynamic>{
    for (final e in data.entries) e.key.toString(): e.value,
  };
}
