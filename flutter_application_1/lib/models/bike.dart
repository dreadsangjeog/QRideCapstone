class Bike {
  Bike({
    required this.id,
    required this.code,
    required this.status,
    this.label,
    this.photoPath,
    this.createdAt,
  });

  final String id;
  final String code;
  final String status; // available | rented | maintenance
  final String? label;
  final String? photoPath;
  final DateTime? createdAt;

  bool get hasPhoto => (photoPath ?? '').trim().isNotEmpty;

  Bike copyWith({
    String? status,
    String? label,
    String? photoPath,
    bool clearPhoto = false,
  }) {
    return Bike(
      id: id,
      code: code,
      status: status ?? this.status,
      label: label ?? this.label,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      createdAt: createdAt,
    );
  }

  factory Bike.fromJson(Map<String, dynamic> json) {
    return Bike(
      id: json['id'].toString(),
      code: (json['code'] ?? '').toString(),
      status: (json['status'] ?? 'available').toString(),
      label: json['label']?.toString(),
      photoPath: json['photo_path']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

