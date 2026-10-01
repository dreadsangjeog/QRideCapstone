import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Live GPS fixes from the Android rental service.
///
/// The listener is [android.location.LocationManager] GPS_PROVIDER, registered
/// for the whole ride. It is not a one-shot read, so the chip stays on when
/// QRide is in the background or the screen is locked.
class RideGpsEvents {
  static const _channel = EventChannel('com.qride.demo/ride_gps');

  static Stream<Position> positions() {
    return _channel.receiveBroadcastStream().map(_toPosition);
  }

  static Position _toPosition(Object? event) {
    if (event is! Map) {
      throw const FormatException('Ride GPS event was not a map');
    }
    final map = <String, dynamic>{
      for (final entry in event.entries) entry.key.toString(): entry.value,
    };
    final headingOk = map['heading_ok'] == true;
    final speedOk = map['speed_ok'] == true;
    final timeMs = (map['time'] as num?)?.toInt() ?? 0;
    final timestamp = timeMs <= 0
        ? DateTime.now().toUtc()
        : DateTime.fromMillisecondsSinceEpoch(timeMs, isUtc: true);

    return Position(
      latitude: (map['lat'] as num).toDouble(),
      longitude: (map['lng'] as num).toDouble(),
      timestamp: timestamp,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      altitude: (map['altitude'] as num?)?.toDouble() ?? 0,
      altitudeAccuracy: 0,
      heading: headingOk ? (map['heading'] as num?)?.toDouble() ?? -1 : -1,
      headingAccuracy: headingOk ? 0 : -1,
      speed: speedOk ? (map['speed'] as num?)?.toDouble() ?? -1 : -1,
      speedAccuracy: speedOk ? 0 : -1,
    );
  }
}
