import 'package:flutter_compass/flutter_compass.dart';

import 'device_compass.dart';

Stream<CompassReading>? get compassEvents {
  final stream = FlutterCompass.events;
  if (stream == null) return null;
  return stream.map((e) => CompassReading(e.heading));
}
