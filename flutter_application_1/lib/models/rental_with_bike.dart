import 'bike.dart';
import 'rental.dart';

class RentalWithBike {
  RentalWithBike({required this.rental, this.bike});

  final Rental rental;
  final Bike? bike;

  factory RentalWithBike.fromJoinedJson(Map<String, dynamic> json) {
    final rental = Rental.fromJson(json);
    Bike? bike;
    final bikeJson = json['bikes'];
    if (bikeJson is Map<String, dynamic>) {
      bike = Bike.fromJson(bikeJson);
    } else if (bikeJson is List && bikeJson.isNotEmpty) {
      final first = bikeJson.first;
      if (first is Map<String, dynamic>) {
        bike = Bike.fromJson(first);
      }
    }
    return RentalWithBike(rental: rental, bike: bike);
  }
}
