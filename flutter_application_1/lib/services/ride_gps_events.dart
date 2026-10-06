import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Live GPS fixes from the Android rental service.
///
/// The native listener stays registered for the whole ride. It is not replaced
/// when the screen locks or QRide is closed, because a new location request
/// started then is ignored until the app is open again.
class RideGpsEvents {
  static const _channel = EventChannel('com.qride.demo/ride_gps');
  static const _control = MethodChannel('com.qride.demo/ride_gps_ctl');

  static Stream<Position> positions() {
    return _channel.receiveBroadcastStream().map(_toPosition);
  }

  /// Asks Android for one fresh point without dropping the ride listener.
  static Future<void> nudge() async {
    try {
      await _control.invokeMethod<void>('nudge');
    } catch (_) {}
  }

  /// Registers the fused listener again. Only call this while QRide is on
  /// screen. A new request made with the screen off is ignored, and the
  /// previous listener is already gone.
  static Future<void> rebind() async {
    try {
      await _control.invokeMethod<void>('rebind');
    } catch (_) {}
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
