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
  });

  final String rentalId;
  final String bikeCode;
  final String bikeLabel;
  final String username;
  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime? recordedAt;

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
      );
    } catch (_) {
      return null;
    }
  }
}
