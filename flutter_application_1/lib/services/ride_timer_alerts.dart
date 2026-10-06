import 'package:shared_preferences/shared_preferences.dart';

/// Time alerts for an active ride.
enum RideTimerAlert {
  fiveMinutes(
    notificationId: 11,
    inboxType: 'rental_five_min',
    title: '5 minutes left',
    body: 'Your rental is about to expire. Head back soon.',
  ),
  overtime(
    notificationId: 12,
    inboxType: 'rental_overtime',
    title: 'Overtime — penalty accruing',
    body: 'Your rental time has passed. A penalty fee is now being added.',
  );

  const RideTimerAlert({
    required this.notificationId,
    required this.inboxType,
    required this.title,
    required this.body,
  });

  final int notificationId;
  final String inboxType;
  final String title;
  final String body;

  static const _prefix = 'qride_timer_alert_';

  /// Records that this alert went out for the ride's current end time and
  /// returns false if it already had.
  ///
  /// The ride screen and the Android rental service both read this record,
  /// from separate isolates, so it is reloaded from disk each time. An
  /// extension moves the end time, which lets the alert go out again.
  Future<bool> claim({
    required String rentalId,
    required DateTime scheduledEnd,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = '$_prefix${name}_$rentalId';
    final end = scheduledEnd.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (prefs.getInt(key) == end) return false;
    await prefs.setInt(key, end);
    final stale = prefs
        .getKeys()
        .where((k) => k.startsWith(_prefix) && !k.endsWith('_$rentalId'))
        .toList();
    for (final k in stale) {
      await prefs.remove(k);
    }
    return true;
  }
}
