class Bike {
  Bike({
    required this.id,
    required this.code,
    required this.status,
    this.label,
  });

  final String id;
  final String code;
  final String status; // available | rented | maintenance
  final String? label;

  factory Bike.fromJson(Map<String, dynamic> json) {
    return Bike(
      id: json['id'].toString(),
      code: (json['code'] ?? '').toString(),
      status: (json['status'] ?? 'available').toString(),
      label: json['label']?.toString(),
    );
  }
}

