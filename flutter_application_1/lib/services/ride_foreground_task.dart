import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../config/supabase_config.dart';

/// Top-level entry used by [FlutterForegroundTask.startService].
@pragma('vm:entry-point')
void rideForegroundStartCallback() {
  FlutterForegroundTask.setTaskHandler(RideLocationTaskHandler());
}

/// Plugin helper kept initialized from [main] for compatibility.
///
/// Active-rental GPS no longer starts this service. Admin uploads use
/// Geolocator’s own location foreground service in [LocationTrackingService]
/// so only one location FGS runs (two at once contended for GPS).
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

  /// Consecutive 401/403 responses → rental ended or session dead; stop FGS.
  int _denyStreak = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadPersisted();
    await _shareOnce();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_shareOnce());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

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

  Future<void> _shareOnce() async {
    if (_busy) return;
    if (_rentalId == null || _userId == null) await _loadPersisted();

    final rentalId = _rentalId;
    final userId = _userId;
    var token = _accessToken;
    if (rentalId == null || userId == null || token == null || token.isEmpty) {
      // Cold start race: tokens not pushed yet — reload once more next tick.
      await _loadPersisted();
      return;
    }

    _busy = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // Fresh fix when possible; on screen-lock / cold GPS fall back to last
      // known so admin still advances instead of stalling for an 8s timeout.
      final pos = await _readPosition();
      if (pos == null) return;

      var result = await _upsertLocation(
        rentalId: rentalId,
        userId: userId,
        token: token,
        pos: pos,
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
          );
        }
      }

      if (result == _UpsertResult.ok) {
        _denyStreak = 0;
        FlutterForegroundTask.sendDataToMain({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy_m': pos.accuracy,
          'heading': pos.heading,
          'at': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      }

      if (result == _UpsertResult.forbidden ||
          result == _UpsertResult.unauthorized) {
        _denyStreak++;
        // Rental ended (RLS) or session unusable — drop the notice.
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
    }
  }

  /// Prefer last-known (fed by the main Geolocator stream/FGS) so this backup
  /// isolate does not contend with getCurrentPosition while screen-locked.
  Future<Position?> _readPosition() async {
    Position? last;
    try {
      last = await Geolocator.getLastKnownPosition();
    } catch (_) {}

    if (last != null) {
      final age = DateTime.now().difference(last.timestamp);
      if (!age.isNegative && age <= const Duration(seconds: 25)) {
        return last;
      }
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
    } catch (_) {
      return last;
    }
  }

  Future<_UpsertResult> _upsertLocation({
    required String rentalId,
    required String userId,
    required String token,
    required Position pos,
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
    if (!pos.heading.isNaN && pos.heading >= 0 && pos.heading <= 360) {
      payload['heading'] = pos.heading;
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

    try {
      await http
          .post(
            Uri.parse('$base/rest/v1/rental_locations'),
            headers: {...headers, 'Prefer': 'return=minimal'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {}

    return _UpsertResult.ok;
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
