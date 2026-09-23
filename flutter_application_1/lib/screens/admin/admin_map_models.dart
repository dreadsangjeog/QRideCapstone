part of 'admin_map_tab.dart';

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

  /// One missed 3-second GPS write → treat as no signal (idle).
  static const staleAfter = Duration(seconds: 4);

  bool get isStale {
    final at = recordedAt;
    if (at == null) return true;
    return DateTime.now().toUtc().difference(at.toUtc()) > staleAfter;
  }

  String get freshnessLabel {
    final at = recordedAt;
    if (at == null) return 'No signal yet';
    final age = DateTime.now().toUtc().difference(at.toUtc());
    if (age.inSeconds < 4) return 'Live now';
    if (age.inSeconds < 60) return 'Last seen ${age.inSeconds}s ago';
    if (age.inMinutes < 60) return 'Last seen ${age.inMinutes}m ago';
    return 'Last seen ${age.inHours}h ago';
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
        recordedAt: json['recorded_at'] == null
            ? null
            : DateTime.tryParse(json['recorded_at'].toString()),
        heading: json['heading'] == null
            ? null
            : (json['heading'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
