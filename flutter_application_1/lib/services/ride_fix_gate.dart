import 'package:geolocator/geolocator.dart';

/// Filters GPS samples for an active rental.
///
/// Android often delivers the last cached point again, with the same
/// timestamp, once the app is in the background. Those repeats must not count
/// as a new fix. A newer sample at the same place still counts, so a bike
/// waiting at a light keeps a fresh timestamp.
class RideFixGate {
  DateTime? _lastSampleTime;
  double? _lastLat;
  double? _lastLng;

  bool accept({
    required DateTime sampleTime,
    required double lat,
    required double lng,
    required double accuracy,
    required DateTime now,
  }) {
    final age = now.difference(sampleTime.toUtc());
    final stale = !age.isNegative && age > const Duration(seconds: 25);
    final lastTime = _lastSampleTime;
    final lastLat = _lastLat;
    final lastLng = _lastLng;

    if (lastTime == null || lastLat == null || lastLng == null) {
      // Seed the pin from a recent cache, not from a fix that is hours old.
      if (stale && age > const Duration(minutes: 2)) return false;
      _remember(sampleTime, lat, lng);
      return true;
    }

    final moved = Geolocator.distanceBetween(lastLat, lastLng, lat, lng);
    final newer = sampleTime.toUtc().isAfter(
      lastTime.toUtc().add(const Duration(milliseconds: 500)),
    );

    if (!newer && moved < 4) return false;
    if (stale && moved < 8) return false;
    if (moved > 2000 && accuracy > 80) return false;

    _remember(sampleTime, lat, lng);
    return true;
  }

  void _remember(DateTime sampleTime, double lat, double lng) {
    _lastSampleTime = sampleTime;
    _lastLat = lat;
    _lastLng = lng;
  }
}

/// Facing direction to store with a rental fix.
///
/// While the bike is moving, direction of travel comes from GPS so a phone
/// in a pocket still points along the ride. While stopped, a fresh compass
/// reading turns the pin in place.
double? chooseRideHeading({
  required DateTime now,
  required double? compass,
  required DateTime? compassAt,
  required double speedMps,
  required double? gpsHeading,
}) {
  final moving = speedMps >= 1.0;
  if (moving && _validHeading(gpsHeading)) return gpsHeading;

  if (compass != null &&
      compassAt != null &&
      now.difference(compassAt) <= const Duration(seconds: 8) &&
      _validHeading(compass)) {
    return compass;
  }

  if (_validHeading(gpsHeading)) return gpsHeading;
  return null;
}

bool _validHeading(double? heading) {
  if (heading == null || heading.isNaN) return false;
  return heading >= 0 && heading <= 360;
}
