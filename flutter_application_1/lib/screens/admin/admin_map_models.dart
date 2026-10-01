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

  /// Rider writes about every 3s. Wider windows + hysteresis (see
  /// [signalWithHysteresis]) avoid yellow/red flicker when a write is late.
  static const liveWithin = Duration(seconds: 30);
  static const delayedWithin = Duration(seconds: 75);

  /// Extra seconds before leaving a band (stops 1Hz timer flicker at edges).
  static const leaveGrace = Duration(seconds: 10);

  /// Must beat the threshold by this much to re-enter a fresher band.
  static const recoverSlack = Duration(seconds: 8);

  Duration? ageFrom(DateTime? at) {
    if (at == null) return null;
    final d = DateTime.now().toUtc().difference(at.toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  Duration? get age => ageFrom(recordedAt);

  _RiderSignal get signal => signalWithHysteresis(null);

  /// Stable signal for map pins — keep prior band until age clearly crosses.
  ///
  /// [anchor] is when the admin last saw a newer fix. That stays smooth when
  /// a late response carries an older `recorded_at`, which was flipping the
  /// pin between red and yellow.
  _RiderSignal signalWithHysteresis(
    _RiderSignal? previous, {
    DateTime? anchor,
  }) {
    final a = ageFrom(anchor ?? recordedAt);
    if (a == null) return _RiderSignal.waiting;

    final prev = previous ?? _RiderSignal.waiting;
    switch (prev) {
      case _RiderSignal.live:
        if (a <= liveWithin + leaveGrace) return _RiderSignal.live;
        if (a <= delayedWithin + leaveGrace) return _RiderSignal.delayed;
        return _RiderSignal.lost;
      case _RiderSignal.delayed:
        if (a <= liveWithin - recoverSlack) return _RiderSignal.live;
        if (a <= delayedWithin + leaveGrace) return _RiderSignal.delayed;
        return _RiderSignal.lost;
      case _RiderSignal.lost:
        if (a <= liveWithin - recoverSlack) return _RiderSignal.live;
        if (a <= delayedWithin - recoverSlack) return _RiderSignal.delayed;
        return _RiderSignal.lost;
      case _RiderSignal.waiting:
        if (a <= liveWithin) return _RiderSignal.live;
        if (a <= delayedWithin) return _RiderSignal.delayed;
        return _RiderSignal.lost;
    }
  }

  bool get isStale =>
      signal == _RiderSignal.lost || signal == _RiderSignal.waiting;
  bool get isLive => signal == _RiderSignal.live;

  String get freshnessLabel => freshnessLabelFor(signal);

  String freshnessLabelFor(_RiderSignal s) {
    switch (s) {
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
      final rentalId = json['rental_id'].toString();
      final rentals = json['rentals'] as Map<String, dynamic>?;
      final bikes = rentals?['bikes'] as Map<String, dynamic>?;
      final profiles = rentals?['profiles'] as Map<String, dynamic>?;
      final code = (bikes?['code'] ?? '').toString().trim();
      // Still show the pin if the bike join is missing (deleted bike, etc.).
      final displayCode =
          code.isEmpty ? 'R${rentalId.length >= 6 ? rentalId.substring(0, 6) : rentalId}' : code;

      final label = (bikes?['label'] ?? '').toString().trim();
      final accRaw = json['accuracy_m'];
      final uname = (profiles?['username'] ?? '').toString().trim();
      final legal = [
        profiles?['first_name'],
        profiles?['middle_name'],
        profiles?['last_name'],
      ]
          .map((s) => (s ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .join(' ');

      return _MarkerRow(
        rentalId: rentalId,
        bikeCode: displayCode,
        bikeLabel: label.isEmpty ? 'Bike $displayCode' : label,
        username: legal.isNotEmpty
            ? legal
            : (uname.isEmpty ? 'Unknown rider' : uname),
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
