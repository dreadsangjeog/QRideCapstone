class Bike {
  Bike({
    required this.id,
    required this.code,
    required this.status,
    this.label,
    this.createdAt,
  });

  final String id;
  final String code;
  final String status; // available | rented | maintenance
  final String? label;
  final DateTime? createdAt;

  factory Bike.fromJson(Map<String, dynamic> json) {
    return Bike(
      id: json['id'].toString(),
      code: (json['code'] ?? '').toString(),
      status: (json['status'] ?? 'available').toString(),
      label: json['label']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

