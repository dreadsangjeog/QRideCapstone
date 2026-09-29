import 'bike.dart';
import 'rental.dart';

class RentalWithBike {
  RentalWithBike({
    required this.rental,
    this.bike,
    this.username,
    this.firstName,
    this.middleName,
    this.lastName,
  });

  final Rental rental;
  final Bike? bike;
  final String? username;
  final String? firstName;
  final String? middleName;
  final String? lastName;

  String get legalName {
    final parts = [firstName, middleName, lastName]
        .map((s) => (s ?? '').trim())
        .where((s) => s.isNotEmpty);
    return parts.join(' ');
  }

  /// Legal name when KYC has it, otherwise the login username.
  String get riderDisplay {
    final name = legalName;
    if (name.isNotEmpty) return name;
    if (username?.trim().isNotEmpty == true) return username!.trim();
    final uid = rental.userId;
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  /// Login username when it is different from [riderDisplay].
  String? get riderUsername {
    final u = username?.trim();
    if (u == null || u.isEmpty) return null;
    if (u.toLowerCase() == riderDisplay.toLowerCase()) return null;
    return u;
  }

  String get bikeDisplay {
    if (bike != null) {
      final label = bike!.label?.trim() ?? '';
      return label.isNotEmpty ? '$label (${bike!.code})' : bike!.code;
    }
    final id = rental.bikeId?.trim();
    if (id == null || id.isEmpty) return 'Removed bike';
    return id.length > 8 ? 'Bike ${id.substring(0, 8)}' : 'Bike $id';
  }

  factory RentalWithBike.fromJoinedJson(Map<String, dynamic> json) {
    final rental = Rental.fromJson(json);

    Bike? bike;
    final bikeJson = json['bikes'];
    if (bikeJson is Map<String, dynamic>) {
      bike = Bike.fromJson(bikeJson);
    } else if (bikeJson is List && bikeJson.isNotEmpty) {
      final first = bikeJson.first;
      if (first is Map<String, dynamic>) bike = Bike.fromJson(first);
    }

    String? username;
    String? firstName;
    String? middleName;
    String? lastName;
    final profileJson = json['profiles'];
    if (profileJson is Map<String, dynamic>) {
      username = profileJson['username']?.toString();
      firstName = profileJson['first_name']?.toString();
      middleName = profileJson['middle_name']?.toString();
      lastName = profileJson['last_name']?.toString();
    }

    return RentalWithBike(
      rental: rental,
      bike: bike,
      username: username,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
  }
}
