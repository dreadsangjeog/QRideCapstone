import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/peso.dart';
import 'notification_repository.dart';
import 'ride_timer_alerts.dart';

/// Wraps flutter_local_notifications for rental-related alerts.
///
/// Notification IDs:
///   10 — rental approved / rejected
///   11 — 5-minute warning
///   12 — overtime started
///   13 — rental ended / receipt
///   20+ — generic inbox banners
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _inboxId = 20;

  static const _prefsSound = 'notif_sound';
  static const _prefsVibrate = 'notif_vibrate';
  static const _prefsBanners = 'notif_banners';

  static bool soundEnabled = true;
  static bool vibrationEnabled = true;
  static bool bannersEnabled = true;
  static DateTime? _lastKycCue;

  /// Null on web, where Int64List is unsupported and there are no
  /// notification channels.
  static final Int64List? _vibratePattern = kIsWeb
      ? null
      : Int64List.fromList(const [0, 280, 120, 280]);

  /// Android 8+ takes sound and vibration from the channel and ignores the
  /// per-notification flags, so each Sound/Vibration/banner choice has its
  /// own channel. Android restores a deleted channel's old settings when its
  /// ID is reused, so an ID must always mean the same choice. Older IDs are
  /// dropped because a channel created once without sound stays silent.
  static const _variants = [
    'svb',
    'svt',
    'snb',
    'snt',
    'qvb',
    'qvt',
    'qnb',
    'qnt',
  ];
  static const _legacyChannels = [
    'qride_rental',
    'qride_kyc',
    'qride_rental_sv',
    'qride_rental_sn',
    'qride_rental_qv',
    'qride_rental_qn',
    'qride_kyc_sv',
    'qride_kyc_sn',
    'qride_kyc_qv',
    'qride_kyc_qn',
  ];

  static String get _variant =>
      '${soundEnabled ? 's' : 'q'}'
      '${vibrationEnabled ? 'v' : 'n'}'
      '${bannersEnabled ? 'b' : 't'}';

  static Importance get _alertImportance => bannersEnabled
      ? Importance.high
      : Importance.defaultImportance;

  static AndroidNotificationChannel get _channel => AndroidNotificationChannel(
        'qride_alerts_$_variant',
        'Rental alerts',
        description:
            'Time warnings, approvals, and receipts for active rentals.',
        importance: _alertImportance,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled ? _vibratePattern : null,
        audioAttributesUsage: AudioAttributesUsage.notification,
      );

  static AndroidNotificationChannel get _kycChannel =>
      AndroidNotificationChannel(
        'qride_identity_$_variant',
        'Identity alerts',
        description: 'When staff approve or reject your ID.',
        importance: bannersEnabled ? Importance.max : Importance.defaultImportance,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled ? _vibratePattern : null,
        audioAttributesUsage: AudioAttributesUsage.notification,
      );

  static Future<void> _syncChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    final rental = _channel;
    final kyc = _kycChannel;
    final unused = [
      ..._legacyChannels,
      for (final v in _variants) ...['qride_rental_$v', 'qride_kyc_$v'],
    ].where((id) => id != rental.id && id != kyc.id);
    for (final id in unused) {
      await android.deleteNotificationChannel(id);
    }
    await android.createNotificationChannel(rental);
    await android.createNotificationChannel(kyc);
  }

  static Future<void> loadPrefs({bool reload = false}) async {
    final p = await SharedPreferences.getInstance();
    if (reload) await p.reload();
    soundEnabled = p.getBool(_prefsSound) ?? true;
    vibrationEnabled = p.getBool(_prefsVibrate) ?? true;
    bannersEnabled = p.getBool(_prefsBanners) ?? true;
  }

  static Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsSound, value);
    if (_ready) await _syncChannels();
  }

  static Future<void> setVibrationEnabled(bool value) async {
    vibrationEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsVibrate, value);
    if (_ready) await _syncChannels();
  }

  static Future<void> setBannersEnabled(bool value) async {
    bannersEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsBanners, value);
    if (_ready) await _syncChannels();
  }

  /// Plays one alert with the current sound, vibration, and banner choices.
  static Future<void> showTestAlert() => _show(
        id: 19,
        title: 'QRide alert test',
        body: 'This is how a rental alert sounds and vibrates.',
      );

  static Future<void> init() async {
    if (_ready) return;
    await loadPrefs();

    const androidSettings =
        AndroidInitializationSettings('ic_launcher_foreground');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: ios),
    );
    await _syncChannels();

    _ready = true;
  }

  static Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
    Importance importance = Importance.high,
    AndroidNotificationChannel? channel,
  }) async {
    await init();
    // Sound and vibration are delivered by the system notification. Turning
    // banners off only lowers it from a pop-up to the tray.
    if (!bannersEnabled && !soundEnabled && !vibrationEnabled) return;
    final used = channel ?? _channel;
    final alertImportance = importance == Importance.max && bannersEnabled
        ? Importance.max
        : used.importance;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          used.id,
          used.name,
          channelDescription: used.description,
          importance: alertImportance,
          priority: alertImportance == Importance.max
              ? Priority.max
              : alertImportance == Importance.high
                  ? Priority.high
                  : Priority.defaultPriority,
          icon: 'ic_launcher_foreground',
          playSound: soundEnabled,
          enableVibration: vibrationEnabled,
          vibrationPattern: vibrationEnabled ? _vibratePattern : null,
          silent: false,
          category: AndroidNotificationCategory.reminder,
          audioAttributesUsage: AudioAttributesUsage.notification,
          visibility: NotificationVisibility.public,
          ticker: title,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: soundEnabled,
          presentAlert: true,
          presentBadge: true,
        ),
      ),
    );
  }

  /// In-app chime + vibration when staff verify the rider.
  static Future<void> playKycVerifiedCue() async {
    await init();
    final now = DateTime.now();
    if (_lastKycCue != null &&
        now.difference(_lastKycCue!) < const Duration(seconds: 4)) {
      return;
    }
    _lastKycCue = now;
    if (soundEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
    if (vibrationEnabled) {
      await HapticFeedback.heavyImpact();
    }
  }

  /// Banner for a new inbox row (from Realtime). Uses rotating IDs so
  /// multiple alerts can stack briefly.
  static Future<void> showInboxBanner(AppNotification n) async {
    final kyc = n.type == 'kyc_verified' || n.type == 'kyc_rejected';
    if (n.type == 'kyc_verified') {
      await playKycVerifiedCue();
    }
    final id = _inboxId;
    _inboxId = 20 + ((_inboxId - 19) % 40);
    final importance = n.type == 'rental_overtime' ||
            n.type == 'rental_ended' ||
            n.type == 'kyc_verified'
        ? Importance.max
        : Importance.high;
    return _show(
      id: id,
      title: n.title,
      body: n.body,
      importance: importance,
      channel: kyc ? _kycChannel : _channel,
    );
  }

  static Future<void> notifyApproved(String bikeLabel) => _show(
        id: 10,
        title: 'Rental approved!',
        body: 'Your ride on $bikeLabel has started. Enjoy!',
      );

  static Future<void> notifyRideTimer(RideTimerAlert alert) => _show(
        id: alert.notificationId,
        title: alert.title,
        body: alert.body,
        importance: alert == RideTimerAlert.overtime
            ? Importance.max
            : Importance.high,
      );

  /// Same alert, posted from the rental service isolate. Its copy of the
  /// switches is reloaded because the rider may have changed them in the app.
  static Future<void> notifyRideTimerFromService(RideTimerAlert alert) async {
    if (_ready) {
      await loadPrefs(reload: true);
      await _syncChannels();
    }
    await notifyRideTimer(alert);
  }

  static Future<void> notifyRentalEnded({
    required double totalCost,
    required double penaltyFee,
  }) =>
      _show(
        id: 13,
        title: 'Rental ended',
        body: penaltyFee > 0
            ? 'Total: ${formatPeso(totalCost)} '
                '(includes ${formatPeso(penaltyFee)} penalty)'
            : 'Total: ${formatPeso(totalCost)}. Thank you!',
        importance: Importance.max,
      );

  static Future<void> notifyRejected() => _show(
        id: 10,
        title: 'Rental request declined',
        body:
            'The admin has declined your request. The bike is now available again.',
      );

  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
