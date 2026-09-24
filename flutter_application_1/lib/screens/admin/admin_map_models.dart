part of 'admin_map_tab.dart';

enum _RiderSignal { waiting, live, delayed, lost }

// ── Data model ────────────────────────────────────────────────────────────────

class _MarkerRow {
  _MarkerRow({
    required this.rentalId,
    required this.bikeCode,
    required this.bikeLabel,
    required this.username,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.recordedAt,
    this.heading,
  });

  final String rentalId;
  final String bikeCode;
  final String bikeLabel;
  final String username;
  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime? recordedAt;
  final double? heading;

  /// Rider writes about every 5s. Allow a few missed uploads + phone clock
  /// skew before we call the pin stale.
  static const liveWithin = Duration(seconds: 20);
  static const delayedWithin = Duration(seconds: 45);

  Duration? get age {
    final at = recordedAt;
    if (at == null) return null;
    final d = DateTime.now().toUtc().difference(at.toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  _RiderSignal get signal {
    final a = age;
    if (a == null) return _RiderSignal.waiting;
    if (a <= liveWithin) return _RiderSignal.live;
    if (a <= delayedWithin) return _RiderSignal.delayed;
    return _RiderSignal.lost;
  }

  bool get isStale =>
      signal == _RiderSignal.lost || signal == _RiderSignal.waiting;
  bool get isLive => signal == _RiderSignal.live;

  String get freshnessLabel {
    switch (signal) {
      case _RiderSignal.waiting:
        return 'Waiting for first GPS share';
      case _RiderSignal.live:
        return 'Sharing location';
      case _RiderSignal.delayed:
        return 'Last update ${_formatAge(age!)} ago';
      case _RiderSignal.lost:
        return 'No update for ${_formatAge(age!)}';
    }
  }

  static String _formatAge(Duration age) {
    if (age.inSeconds < 60) return '${age.inSeconds}s';
    if (age.inMinutes < 60) return '${age.inMinutes}m';
    return '${age.inHours}h';
  }

  static DateTime? parseRecordedAt(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final hasZone =
        s.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(s) ||
        RegExp(r'[+-]\d{4}$').hasMatch(s);
    return DateTime.tryParse(hasZone ? s : '${s}Z');
  }

  static _MarkerRow? fromJoined(Map<String, dynamic> json) {
    try {
      final rentals = json['rentals'] as Map<String, dynamic>?;
      final bikes = rentals?['bikes'] as Map<String, dynamic>?;
      final profiles = rentals?['profiles'] as Map<String, dynamic>?;
      final code = (bikes?['code'] ?? '').toString().trim();
      if (code.isEmpty) return null;

      final label = (bikes?['label'] ?? '').toString().trim();
      final accRaw = json['accuracy_m'];
      final uname = (profiles?['username'] ?? '').toString().trim();

      return _MarkerRow(
        rentalId: json['rental_id'].toString(),
        bikeCode: code,
        bikeLabel: label.isEmpty ? 'Bike $code' : label,
        username: uname.isEmpty ? 'Unknown rider' : uname,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyM: accRaw == null ? null : (accRaw as num).toDouble(),
        recordedAt: parseRecordedAt(json['recorded_at']),
        heading: json['heading'] == null
            ? null
            : (json['heading'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
