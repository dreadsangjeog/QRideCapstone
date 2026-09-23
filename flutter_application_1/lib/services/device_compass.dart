import 'device_compass_stub.dart'
    if (dart.library.io) 'device_compass_io.dart' as impl;

class CompassReading {
  const CompassReading(this.heading);
  final double? heading;
}

abstract final class DeviceCompass {
  static Stream<CompassReading>? get events => impl.compassEvents;
}
