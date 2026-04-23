class RentalLocation {
  RentalLocation({
    required this.rentalId,
    required this.userId,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.recordedAt,
  });

  final String rentalId;
  final String userId;
  final double lat;
  final double lng;
  final double? accuracyM;
  final DateTime recordedAt;

  factory RentalLocation.fromJson(Map<String, dynamic> json) {
    return RentalLocation(
      rentalId: json['rental_id'].toString(),
      userId: json['user_id'].toString(),
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      accuracyM: json['accuracy_m'] == null
          ? null
          : (json['accuracy_m'] as num).toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'].toString()),
    );
  }
}

