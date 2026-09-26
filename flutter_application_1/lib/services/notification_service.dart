import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_repository.dart';

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

  static const _channel = AndroidNotificationChannel(
    'qride_rental',
    'Rental Alerts',
    description: 'Time warnings, approvals, and receipts for active rentals.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _kycChannel = AndroidNotificationChannel(
    'qride_kyc',
    'Identity alerts',
    description: 'When staff approve or reject your ID.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    soundEnabled = p.getBool(_prefsSound) ?? true;
    vibrationEnabled = p.getBool(_prefsVibrate) ?? true;
    bannersEnabled = p.getBool(_prefsBanners) ?? true;
  }

  static Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsSound, value);
  }

  static Future<void> setVibrationEnabled(bool value) async {
    vibrationEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsVibrate, value);
  }

  static Future<void> setBannersEnabled(bool value) async {
    bannersEnabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefsBanners, value);
  }

  static Future<void> init() async {
    if (_ready) return;
    await loadPrefs();

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
    await androidPlugin?.createNotificationChannel(_kycChannel);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: ios),
    );

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
    if (!bannersEnabled) return;
    final used = channel ?? _channel;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          used.id,
          used.name,
          channelDescription: used.description,
          importance: importance,
          priority: importance == Importance.max
              ? Priority.max
              : Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: soundEnabled,
          enableVibration: vibrationEnabled,
          silent: !soundEnabled && !vibrationEnabled,
          category: AndroidNotificationCategory.status,
          audioAttributesUsage: AudioAttributesUsage.notification,
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

  static Future<void> notifyFiveMinuteWarning() => _show(
        id: 11,
        title: '5 minutes left',
        body: 'Your rental is about to expire. Head back soon.',
      );

  static Future<void> notifyOvertimeStarted() => _show(
        id: 12,
        title: 'Overtime — penalty accruing',
        body: 'Your rental time has passed. A penalty fee is now being added.',
        importance: Importance.max,
      );

  static Future<void> notifyRentalEnded({
    required double totalCost,
    required double penaltyFee,
  }) =>
      _show(
        id: 13,
        title: 'Rental ended',
        body: penaltyFee > 0
            ? 'Total: ₱${totalCost.toStringAsFixed(2)} '
                '(includes ₱${penaltyFee.toStringAsFixed(2)} penalty)'
            : 'Total: ₱${totalCost.toStringAsFixed(2)}. Thank you!',
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
