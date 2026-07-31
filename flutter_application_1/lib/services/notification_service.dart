import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wraps flutter_local_notifications for rental-related alerts.
///
/// Notification IDs:
///   10 — rental approved
///   11 — 5-minute warning
///   12 — overtime started
///   13 — rental ended / receipt
class NotificationService {
  NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channel = AndroidNotificationChannel(
    'qride_rental',
    'Rental Alerts',
    description: 'Time warnings, approvals, and receipts for active rentals.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> init() async {
    if (_ready) return;

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
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
  }) async {
    await init();
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: importance,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
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
        body: 'The admin has declined your request. The bike is now available again.',
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
