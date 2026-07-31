import 'rental.dart';

/// One ended/rejected rental row for history UI (bike labels from join).
class RentalHistoryRow {
  const RentalHistoryRow({
    required this.rental,
    required this.bikeName,
    required this.bikeCode,
  });

  final Rental rental;
  final String bikeName;
  final String bikeCode;
}
