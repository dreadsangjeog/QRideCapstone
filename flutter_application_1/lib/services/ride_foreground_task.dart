import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../config/supabase_config.dart';
import '../utils/jwt_claims.dart';
import 'device_compass.dart';
import 'notification_service.dart';
import 'ride_fix_gate.dart';
import 'ride_gps_events.dart';
import 'ride_timer_alerts.dart';

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
  static const _kMode = 'qride_mode';
  static const _kFixAt = 'qride_fix_at';

  /// Service is up, but GPS stays off until staff approve.
  static const modeWait = 'wait';

  /// Service is uploading location for an active rental.
  static const modeShare = 'share';

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
    required bool sharing,
  }) async {
    if (!_isAndroid) return;
    init();
    await ensureNotificationPermission();
    await _persistContext(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      mode: sharing ? modeShare : modeWait,
    );

    if (await FlutterForegroundTask.isRunningService) {
      // Do not restart — that drops in-flight GPS writes. Just refresh context.
      pushContext(
        rentalId: rentalId,
        userId: userId,
        accessToken: accessToken,
        refreshToken: refreshToken,
        mode: sharing ? modeShare : modeWait,
      );
      if (sharing) await _showSharingNotice();
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 2601,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: sharing ? 'Rental in progress' : 'Rental requested',
      notificationText: sharing ? _sharingNotice : _waitingNotice,
      callback: rideForegroundStartCallback,
    );
  }

  static const _waitingNotice =
      'Waiting for staff. Location starts when they approve, even if QRide is closed.';
  static const _sharingNotice =
      'Sharing bike location. Stays on if you leave QRide, lock the phone, or close the app.';

  static Future<void> _showSharingNotice() async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Rental in progress',
        notificationText: _sharingNotice,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] notice update failed: $e');
    }
  }

  /// Keeps a running service on the current rental + fresh auth without a
  /// full restart when nothing changed. Starts GPS sharing.
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
      mode: modeShare,
    );
    pushContext(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      mode: modeShare,
    );
    if (await FlutterForegroundTask.isRunningService) {
      await _showSharingNotice();
      return;
    }
    await start(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      sharing: true,
    );
  }

  /// Starts the rental notice while the request is still pending.
  ///
  /// The service is started from the open app, then stays up if the rider
  /// leaves or closes QRide. It does not read GPS until the rental is active,
  /// so approval can begin sharing without the rider opening the app again.
  static Future<void> ensureWaiting({
    required String rentalId,
    required String userId,
    required String accessToken,
    String? refreshToken,
  }) async {
    if (!_isAndroid) return;
    init();
    final running = await FlutterForegroundTask.isRunningService;
    final mode = await FlutterForegroundTask.getData<String>(key: _kMode);
    if (running && mode == modeShare) return;
    await start(
      rentalId: rentalId,
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
      sharing: false,
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
    await FlutterForegroundTask.removeData(key: _kMode);
    await FlutterForegroundTask.removeData(key: _kFixAt);
  }

  static Future<bool> get isRunning async {
    if (!_isAndroid) return false;
    return FlutterForegroundTask.isRunningService;
  }

  /// When the service last received a live satellite fix.
  ///
  /// Saved by the ride isolate, so the UI can still see it after the activity
  /// was destroyed. A missing or old value means the listener has stopped.
  static Future<DateTime?> lastFixAt() async {
    if (!_isAndroid) return null;
    final raw = await FlutterForegroundTask.getData<String>(key: _kFixAt);
    final ms = int.tryParse(raw ?? '');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// The login the service last saved. Newer than the app's copy when the
  /// service renewed it while QRide was closed.
  static Future<({String userId, String accessToken, String refreshToken})?>
      savedSession() async {
    if (!_isAndroid) return null;
    final userId = await FlutterForegroundTask.getData<String>(key: _kUserId);
    final access = await FlutterForegroundTask.getData<String>(
      key: _kAccessToken,
    );
    final refresh = await FlutterForegroundTask.getData<String>(
      key: _kRefreshToken,
    );
    if (userId == null || userId.isEmpty) return null;
    if (access == null || access.isEmpty) return null;
    if (refresh == null || refresh.isEmpty) return null;
    return (userId: userId, accessToken: access, refreshToken: refresh);
  }

  static void pushContext({
    required String rentalId,
    required String userId,
    required String accessToken,
    String? refreshToken,
    String? mode,
  }) {
    if (!_isAndroid) return;
    FlutterForegroundTask.sendDataToTask({
      'rental_id': rentalId,
      'user_id': userId,
      'access_token': accessToken,
      'refresh_token': ?refreshToken,
      'mode': ?mode,
    });
  }

  /// Asks the running ride service to open the GPS listener again.
  ///
  /// Used when QRide returns to the screen after a long lock. A new location
  /// request is honored then. Doing it while the screen is still off is not.
  static void reopenGps() {
    if (!_isAndroid) return;
    try {
      FlutterForegroundTask.sendDataToTask({'gps_relisten': true});
    } catch (_) {}
  }

  /// Starts the ride service's engine again. The listener inside a service
  /// that survived a long lock can be dead while the notification is still up.
  static Future<bool> restartWriter() async {
    if (!_isAndroid) return false;
    if (!await FlutterForegroundTask.isRunningService) return false;
    final result = await FlutterForegroundTask.restartService();
    if (result is ServiceRequestFailure) {
      // ignore: avoid_print
      print('[RideFgTask] restart failed: ${result.error}');
      return false;
    }
    return true;
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
    required String mode,
  }) async {
    await FlutterForegroundTask.saveData(key: _kRentalId, value: rentalId);
    await FlutterForegroundTask.saveData(key: _kUserId, value: userId);
    await FlutterForegroundTask.saveData(key: _kMode, value: mode);
    final saved = await FlutterForegroundTask.getData<String>(
      key: _kAccessToken,
    );
    if (_expiresBefore(accessToken, saved)) return;
    await FlutterForegroundTask.saveData(key: _kAccessToken, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await FlutterForegroundTask.saveData(
        key: _kRefreshToken,
        value: refreshToken,
      );
    }
  }
}

/// True when [token] expires before [other]. A pair the app sent before it
/// picked up the service's renewal must not replace the newer one: its
/// refresh token is already spent.
bool _expiresBefore(String token, String? other) {
  final a = jwtExpiry(token);
  final b = jwtExpiry(other);
  return a != null && b != null && a < b;
}

class RideLocationTaskHandler extends TaskHandler {
  String? _accessToken;
  String? _refreshToken;
  String? _rentalId;
  String? _userId;
  bool _sharing = false;
  bool _busy = false;
  bool _shareQueued = false;
  bool _watchBusy = false;
  bool _promoting = false;
  DateTime? _lastWatchAt;
  DateTime? _lastNudgeAt;
  int _listenGen = 0;
  Position? _lastPos;
  DateTime? _lastFixAt;
  DateTime? _lastFixSavedAt;
  DateTime? _lastUploadAt;
  DateTime? _lastRestartAt;
  double? _compassHeading;
  DateTime? _compassAt;
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<CompassReading>? _compassSub;
  final RideFixGate _gate = RideFixGate();

  /// Consecutive 401/403 responses → rental ended or session dead; stop FGS.
  int _denyStreak = 0;

  Future<String?>? _refreshing;
  DateTime? _lastRideCheckAt;
  bool _rideCheckBusy = false;
  DateTime? _scheduledEnd;
  final Set<String> _timerAlertsSeen = {};

  static const _rideCheckEvery = Duration(seconds: 30);

  /// The ride screen posts the time alerts on the second. The service waits
  /// this much longer, then posts any the app did not.
  static const _timerAlertGrace = Duration(seconds: 20);

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _loadPersisted();
    if (!_sharing) {
      await _watchApproval();
      return;
    }
    _startCompass();
    await _listenGps();
    await _shareLatest();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_sharing) {
      unawaited(_watchApproval());
      return;
    }
    unawaited(_shareLatest());
    unawaited(_ensureGpsAlive());
    unawaited(_checkRide());
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
    if (access != null &&
        access.isNotEmpty &&
        !_expiresBefore(access, _accessToken)) {
      _accessToken = access;
      if (refresh != null && refresh.isNotEmpty) _refreshToken = refresh;
    }
    final mode = map['mode']?.toString();
    if (mode == RideForegroundTask.modeShare) {
      unawaited(_promoteToSharing());
    }
    if (map['gps_relisten'] == true && _sharing) {
      unawaited(_reopenGpsListener());
    }
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
    final mode = await FlutterForegroundTask.getData<String>(
      key: RideForegroundTask._kMode,
    );
    // Older sessions have no mode. Those were started only for an active ride.
    _sharing = mode != RideForegroundTask.modeWait;
  }

  /// Polls the rental while the rider is away. GPS stays off until approval.
  Future<void> _watchApproval() async {
    if (_sharing || _watchBusy) return;
    final now = DateTime.now();
    final last = _lastWatchAt;
    if (last != null && now.difference(last) < const Duration(seconds: 4)) {
      return;
    }
    _lastWatchAt = now;
    _watchBusy = true;
    try {
      if (_rentalId == null || _accessToken == null) await _loadPersisted();
      final status = (await _fetchRentalWithRefresh())?.status;

      if (status == 'active') {
        await _promoteToSharing();
        return;
      }
      if (status == 'ended' || status == 'rejected' || status == 'gone') {
        // ignore: avoid_print
        print('[RideFgTask] stopping — request is no longer open');
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] approval watch failed: $e');
    } finally {
      _watchBusy = false;
    }
  }

  Future<void> _promoteToSharing() async {
    if (_promoting || (_sharing && _gpsSub != null)) return;
    _promoting = true;
    try {
      _sharing = true;
      await FlutterForegroundTask.saveData(
        key: RideForegroundTask._kMode,
        value: RideForegroundTask.modeShare,
      );
      await RideForegroundTask._showSharingNotice();
      if (_gpsSub != null) return;
      _startCompass();
      await _listenGps();
      await _shareLatest();
    } finally {
      _promoting = false;
    }
  }

  /// Status is `unauthorized`, `gone`, or the rental status. Null when the
  /// network failed.
  Future<({String status, DateTime? scheduledEnd})?> _fetchRental(
    String rentalId,
    String token,
  ) async {
    final base = SupabaseConfig.effectiveUrl;
    final anon = SupabaseConfig.effectiveAnonKey;
    final uri = Uri.parse(
      '$base/rest/v1/rentals?id=eq.$rentalId'
      '&select=status,approved_at,planned_minutes',
    );
    final response = await http
        .get(
          uri,
          headers: {
            'apikey': anon,
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 401 || response.statusCode == 403) {
      return (status: 'unauthorized', scheduledEnd: null);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    const gone = (status: 'gone', scheduledEnd: null);
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return gone;
    final row = decoded.first;
    if (row is! Map) return gone;
    final status = row['status']?.toString();
    if (status == null || status.isEmpty) return gone;
    final approvedAt = DateTime.tryParse(row['approved_at']?.toString() ?? '');
    final minutes = row['planned_minutes'];
    final end = approvedAt != null && minutes is num
        ? approvedAt.toUtc().add(Duration(minutes: minutes.toInt()))
        : null;
    return (status: status, scheduledEnd: end);
  }

  Future<({String status, DateTime? scheduledEnd})?>
      _fetchRentalWithRefresh() async {
    final rentalId = _rentalId;
    final token = _accessToken;
    if (rentalId == null || token == null || token.isEmpty) return null;
    final rental = await _fetchRental(rentalId, token);
    if (rental?.status != 'unauthorized') return rental;
    final refreshed = await _tryRefreshToken();
    if (refreshed == null) return rental;
    return _fetchRental(rentalId, refreshed);
  }

  /// Stops the service once staff end the ride. Refused uploads also stop it,
  /// but nothing is uploaded while GPS is quiet, such as indoors after the
  /// bike is returned.
  Future<void> _checkRide() async {
    if (_rideCheckBusy) return;
    _rideCheckBusy = true;
    try {
      final last = _lastRideCheckAt;
      if (last == null ||
          DateTime.now().difference(last) >= _rideCheckEvery) {
        _lastRideCheckAt = DateTime.now();
        final rental = await _fetchRentalWithRefresh();
        final status = rental?.status;
        if (status == 'ended' || status == 'rejected' || status == 'gone') {
          // ignore: avoid_print
          print('[RideFgTask] stopping — ride is closed');
          FlutterForegroundTask.sendDataToMain({
            'stopped': true,
            'reason': 'closed',
          });
          await FlutterForegroundTask.stopService();
          return;
        }
        if (status == 'active') _scheduledEnd = rental?.scheduledEnd;
      }
      await _postMissedTimerAlert();
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] ride check failed: $e');
    } finally {
      _rideCheckBusy = false;
    }
  }

  /// Posts the 5-minute or overtime alert when QRide is closed or missed it.
  Future<void> _postMissedTimerAlert() async {
    final end = _scheduledEnd;
    final rentalId = _rentalId;
    if (end == null || rentalId == null) return;
    final left = end.difference(DateTime.now().toUtc());
    final RideTimerAlert alert;
    if (left <= -_timerAlertGrace) {
      alert = RideTimerAlert.overtime;
    } else if (left > Duration.zero &&
        left <= const Duration(minutes: 5) - _timerAlertGrace) {
      alert = RideTimerAlert.fiveMinutes;
    } else {
      return;
    }
    if (!_timerAlertsSeen.add('${alert.name}@${end.millisecondsSinceEpoch}')) {
      return;
    }
    final first = await alert.claim(rentalId: rentalId, scheduledEnd: end);
    if (!first) return;
    try {
      await NotificationService.notifyRideTimerFromService(alert);
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] timer alert failed: $e');
    }
    await _insertTimerInboxRow(alert, rentalId);
  }

  Future<void> _insertTimerInboxRow(
    RideTimerAlert alert,
    String rentalId,
  ) async {
    final userId = _userId;
    final token = _accessToken;
    if (userId == null || token == null || token.isEmpty) return;
    final base = SupabaseConfig.effectiveUrl;
    final anon = SupabaseConfig.effectiveAnonKey;
    try {
      await http
          .post(
            Uri.parse('$base/rest/v1/notifications'),
            headers: {
              'apikey': anon,
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode({
              'user_id': userId,
              'role_scope': 'user',
              'type': alert.inboxType,
              'title': alert.title,
              'body': alert.body,
              'data': {'rental_id': rentalId},
            }),
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      // ignore: avoid_print
      print('[RideFgTask] timer inbox row failed: $e');
    }
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

  /// One GPS subscription for the whole ride. It is not replaced when the
  /// screen locks or QRide is closed: that new request is ignored until the
  /// app is open again, which is what made the pin freeze.
  Future<void> _listenGps() async {
    final gen = ++_listenGen;
    await _gpsSub?.cancel();
    if (gen != _listenGen) return;
    _gpsSub = null;
    _lastRestartAt = DateTime.now();

    _gpsSub = RideGpsEvents.positions().listen(
      (pos) {
        if (gen != _listenGen) return;
        _onFix(pos);
      },
      onError: (Object e) {
        if (gen != _listenGen) return;
        // ignore: avoid_print
        print('[RideFgTask] gps stream error: $e');
        _gpsSub = null;
      },
      onDone: () {
        if (gen != _listenGen) return;
        _gpsSub = null;
      },
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
    if (fresh) {
      _lastFixAt = DateTime.now();
      _rememberLiveFix();
    }
    if (kept || fresh) unawaited(_shareLatest());
  }

  /// Opens the GPS listener again now that QRide is on screen.
  ///
  /// A healthy stream is left alone. A quiet one is registered again, because
  /// that request is only accepted while QRide is visible. The subscription is
  /// not cancelled first: cancelling it used to remove the only listener
  /// Android would still deliver to.
  Future<void> _reopenGpsListener() async {
    if (_gpsSub == null) {
      await _listenGps();
    }
    final fixAt = _lastFixAt;
    final quiet = fixAt == null ||
        DateTime.now().difference(fixAt) > const Duration(seconds: 15);
    if (!quiet) {
      await RideGpsEvents.nudge();
      return;
    }
    await RideGpsEvents.rebind();
  }

  void _rememberLiveFix() {
    final now = DateTime.now().toUtc();
    final prev = _lastFixSavedAt;
    if (prev != null && now.difference(prev) < const Duration(seconds: 3)) {
      return;
    }
    _lastFixSavedAt = now;
    unawaited(
      FlutterForegroundTask.saveData(
        key: RideForegroundTask._kFixAt,
        value: now.millisecondsSinceEpoch.toString(),
      ),
    );
  }

  /// Keeps the original listener. A quiet chip gets one fresh read. The
  /// listener is opened again only if it actually closed.
  Future<void> _ensureGpsAlive() async {
    final now = DateTime.now();
    if (_gpsSub == null) {
      final restarted = _lastRestartAt;
      if (restarted != null &&
          now.difference(restarted) < const Duration(seconds: 8)) {
        return;
      }
      await _listenGps();
      return;
    }
    final fixAt = _lastFixAt;
    final quiet =
        fixAt == null || now.difference(fixAt) > const Duration(seconds: 20);
    if (!quiet) return;
    final nudged = _lastNudgeAt;
    if (nudged != null && now.difference(nudged) < const Duration(seconds: 15)) {
      return;
    }
    _lastNudgeAt = now;
    await RideGpsEvents.nudge();
  }

  Future<void> _shareLatest() async {
    if (_busy) {
      _shareQueued = true;
      return;
    }
    if (!_sharing) return;
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

  /// Renews the login shared with the app. The old refresh token stops
  /// working, so the new pair is saved and sent to the app right away.
  /// Callers that hit an expired token together share one renewal.
  Future<String?> _tryRefreshToken() {
    return _refreshing ??=
        _renewSession().whenComplete(() => _refreshing = null);
  }

  Future<String?> _renewSession() async {
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
      if (access == null || access.isEmpty) return null;
      _accessToken = access;
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        _refreshToken = nextRefresh;
        await FlutterForegroundTask.saveData(
          key: RideForegroundTask._kRefreshToken,
          value: nextRefresh,
        );
      }
      await FlutterForegroundTask.saveData(
        key: RideForegroundTask._kAccessToken,
        value: access,
      );
      final pairRefresh = _refreshToken;
      if (pairRefresh != null && pairRefresh.isNotEmpty) {
        FlutterForegroundTask.sendDataToMain({
          'auth_access_token': access,
          'auth_refresh_token': pairRefresh,
        });
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
