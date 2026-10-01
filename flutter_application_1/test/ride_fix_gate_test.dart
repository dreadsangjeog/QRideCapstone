import 'package:flutter_application_1/services/ride_fix_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached repeat is ignored and a newer point is kept', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    final now = t0.add(const Duration(seconds: 2));

    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: now,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: now.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 4)),
        lat: 14.601,
        lng: 121.0,
        accuracy: 8,
        now: now.add(const Duration(seconds: 4)),
      ),
      isTrue,
    );
  });

  test('hours-old cache is not used as the first fix', () {
    final gate = RideFixGate();
    final now = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: now.subtract(const Duration(hours: 5)),
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: now,
      ),
      isFalse,
    );
  });

  test('absurd jump with poor accuracy is dropped', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 10,
        now: t0,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.8,
        lng: 121.0,
        accuracy: 200,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('moving ride uses GPS course, stopped ride uses compass', () {
    final now = DateTime.utc(2026, 10, 1, 12);
    expect(
      chooseRideHeading(
        now: now,
        compass: 10,
        compassAt: now,
        speedMps: 4,
        gpsHeading: 90,
      ),
      90,
    );
    expect(
      chooseRideHeading(
        now: now,
        compass: 10,
        compassAt: now,
        speedMps: 0,
        gpsHeading: 90,
      ),
      10,
    );
    expect(
      chooseRideHeading(
        now: now,
        compass: 10,
        compassAt: now.subtract(const Duration(seconds: 30)),
        speedMps: 0,
        gpsHeading: 90,
      ),
      90,
    );
  });
}
