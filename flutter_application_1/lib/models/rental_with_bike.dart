import 'bike.dart';
import 'rental.dart';

class RentalWithBike {
  RentalWithBike({required this.rental, this.bike, this.username});

  final Rental rental;
  final Bike? bike;
  final String? username;

  String get riderDisplay {
    if (username?.isNotEmpty == true) return username!;
    // Fallback: show first 8 chars of UUID so it's readable but not a full UUID wall.
    final uid = rental.userId;
    return uid.length > 8 ? uid.substring(0, 8) : uid;
  }

  String get bikeDisplay {
    if (bike == null) return rental.bikeId;
    final label = bike!.label?.trim() ?? '';
    return label.isNotEmpty ? '$label (${bike!.code})' : bike!.code;
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
    final profileJson = json['profiles'];
    if (profileJson is Map<String, dynamic>) {
      username = profileJson['username']?.toString();
    }

    return RentalWithBike(rental: rental, bike: bike, username: username);
  }
}
