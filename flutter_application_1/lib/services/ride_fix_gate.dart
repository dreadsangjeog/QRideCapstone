import 'package:geolocator/geolocator.dart';

/// Filters GPS samples for an active rental.
///
/// A campus bike cannot cross the map in one reading. Android still delivers
/// those points: a cached fix, a cell-tower guess, or a GPS glitch that claims
/// to be accurate. One of those used to move the pin. A real ride still
/// passes, and three accurate readings that agree can catch the pin up after
/// a gap.
class RideFixGate {
  DateTime? _lastSampleTime;
  DateTime? _lastAcceptedAt;
  double? _lastLat;
  double? _lastLng;
  int _rejectStreak = 0;
  double? _rejectLat;
  double? _rejectLng;

  /// Faster than a campus bike, including a downhill. A 3-second step at this
  /// speed is about 45 m before the small GPS-noise allowance.
  static const maxSpeedMps = 15.0;

  static const _noiseM = 30.0;
  static const _coarseAccuracyM = 65.0;
  static const _coarseMaxMoveM = 25.0;
  static const _clusterRadiusM = 30.0;
  static const _clusterNeeded = 3;
  static const _seedMaxAccuracyM = 50.0;

  /// A tight fix shorter than this is standing-still wobble, not a new place.
  static const _deadbandM = 5.0;

  /// A fuzzy fix wanders farther than a tight one. Keep the wider hold for it.
  static const _looseDeadbandM = 12.0;

  /// A tight fix may move this far in one sample without a second opinion.
  /// Farther than that is the next street over until another sample agrees.
  static const _glideM = 24.0;

  static const _looseAccuracyM = 25.0;
  static const _looseGlideM = 12.0;
  static const _confirmRadiusM = 28.0;

  bool accept({
    required DateTime sampleTime,
    required double lat,
    required double lng,
    required double accuracy,
    required DateTime now,
  }) {
    final sampleUtc = sampleTime.toUtc();
    final age = now.toUtc().difference(sampleUtc);
    final lastTime = _lastSampleTime;
    final lastLat = _lastLat;
    final lastLng = _lastLng;

    if (lastTime == null || lastLat == null || lastLng == null) {
      // A recent, tight fix can place the pin. An old or cell-tower point
      // cannot — the next real GPS reading would throw it across the map.
      if (!age.isNegative && age > const Duration(seconds: 45)) return false;
      if (accuracy > _seedMaxAccuracyM) return false;
      _clearCluster();
      _remember(sampleUtc, lat, lng, now);
      return true;
    }

    // A cached point with an old satellite time must not relocate the pin.
    if (!age.isNegative && age > const Duration(seconds: 20)) return false;

    // The chip was quiet through a long screen lock. The next tight, fresh
    // fix is where the bike is now. Checking it against the old pin made
    // the marker stay frozen after QRide was opened again.
    final acceptedAt = _lastAcceptedAt;
    final quietFor = acceptedAt == null
        ? Duration.zero
        : now.toUtc().difference(acceptedAt.toUtc());
    final fresh = age.isNegative || age <= const Duration(seconds: 15);
    if (quietFor > const Duration(seconds: 30) && fresh && accuracy <= 25) {
      _clearCluster();
      _remember(sampleUtc, lat, lng, now);
      return true;
    }

    final moved = Geolocator.distanceBetween(lastLat, lastLng, lat, lng);
    final elapsedSec =
        sampleUtc.difference(lastTime.toUtc()).inMilliseconds / 1000.0;

    // Same cached timestamp, or a late duplicate. Not a new place.
    if (elapsedSec < 0.5) return false;

    // Standing still, the chip still wanders. A tight fix follows after 5 m.
    // A fuzzy one still has to clear 12 m so it cannot creep the pin.
    final deadband = accuracy > _looseAccuracyM ? _looseDeadbandM : _deadbandM;
    if (moved < deadband) {
      _lastSampleTime = sampleUtc;
      _lastAcceptedAt = now.toUtc();
      _clearCluster();
      return false;
    }

    final window = elapsedSec < 1 ? 1.0 : elapsedSec;
    final maxMove = maxSpeedMps * window + _noiseM;
    final tooFast = moved > maxMove;
    final tooCoarse = accuracy > _coarseAccuracyM && moved > _coarseMaxMoveM;
    if (tooFast || tooCoarse) {
      _noteReject(lat, lng, accuracy);
      if (_rejectStreak >= _clusterNeeded) {
        _clearCluster();
        _remember(sampleUtc, lat, lng, now);
        return true;
      }
      return false;
    }

    final glide = accuracy > _looseAccuracyM ? _looseGlideM : _glideM;
    if (moved > glide) {
      return _confirmAway(
        sampleUtc: sampleUtc,
        lat: lat,
        lng: lng,
        moved: moved,
        now: now,
      );
    }

    _clearCluster();
    _remember(sampleUtc, lat, lng, now);
    return true;
  }

  /// A jump onto the next street waits for one more sample.
  ///
  /// If that sample comes back beside the pin, the jump was a glitch and is
  /// dropped. If it stays near the jump, the bike really moved.
  bool _confirmAway({
    required DateTime sampleUtc,
    required double lat,
    required double lng,
    required double moved,
    required DateTime now,
  }) {
    final candLat = _rejectLat;
    final candLng = _rejectLng;
    if (_rejectStreak == 0 || candLat == null || candLng == null) {
      _rejectStreak = 1;
      _rejectLat = lat;
      _rejectLng = lng;
      return false;
    }
    final fromCand = Geolocator.distanceBetween(candLat, candLng, lat, lng);
    final cameBack = moved <= _glideM;
    final stayed = fromCand <= _confirmRadiusM;
    if (cameBack || stayed) {
      _clearCluster();
      _remember(sampleUtc, lat, lng, now);
      return true;
    }
    _rejectStreak = 1;
    _rejectLat = lat;
    _rejectLng = lng;
    return false;
  }

  void _noteReject(double lat, double lng, double accuracy) {
    final prevLat = _rejectLat;
    final prevLng = _rejectLng;
    if (accuracy <= 45 && prevLat != null && prevLng != null) {
      final cluster = Geolocator.distanceBetween(prevLat, prevLng, lat, lng);
      _rejectStreak = cluster <= _clusterRadiusM ? _rejectStreak + 1 : 1;
    } else if (accuracy <= 45) {
      _rejectStreak = 1;
    } else {
      _rejectStreak = 0;
    }
    _rejectLat = lat;
    _rejectLng = lng;
  }

  void _clearCluster() {
    _rejectStreak = 0;
    _rejectLat = null;
    _rejectLng = null;
  }

  void _remember(DateTime sampleTime, double lat, double lng, DateTime now) {
    _lastSampleTime = sampleTime;
    _lastAcceptedAt = now.toUtc();
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
