class Rental {
  Rental({
    required this.id,
    required this.bikeId,
    required this.userId,
    required this.startedAt,
    this.endedAt,
    required this.status,
  });

  final String id;
  final String bikeId;
  final String userId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status; // active | ended

  factory Rental.fromJson(Map<String, dynamic> json) {
    return Rental(
      id: json['id'].toString(),
      bikeId: json['bike_id'].toString(),
      userId: json['user_id'].toString(),
      startedAt: DateTime.parse(json['started_at'].toString()),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'].toString()),
      status: (json['status'] ?? 'active').toString(),
    );
  }
}

