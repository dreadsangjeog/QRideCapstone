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
        lat: 14.60018,
        lng: 121.0,
        accuracy: 8,
        now: now.add(const Duration(seconds: 4)),
      ),
      isTrue,
    );
  });

  test('a far jump in a few seconds is dropped even when accuracy looks good', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    // About 200 m north, three seconds later. Too fast for a bike.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.6018,
        lng: 121.0,
        accuracy: 12,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('a short step is kept and standing-still wobble is not', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    // About 3 m. The chip does this while the bike is parked.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.60003,
        lng: 121.0,
        accuracy: 8,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
    // About 7 m with a tight fix. The pin follows.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 6)),
        lat: 14.60006,
        lng: 121.0,
        accuracy: 8,
        now: t0.add(const Duration(seconds: 6)),
      ),
      isTrue,
    );
    // About 8 m, but the fix is fuzzy. Leave the pin.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 9)),
        lat: 14.60013,
        lng: 121.0,
        accuracy: 40,
        now: t0.add(const Duration(seconds: 9)),
      ),
      isFalse,
    );
  });

  test('a normal bike step is kept', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    // About 18 m in 3 seconds. A normal step, not a hop to the next street.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.60016,
        lng: 121.0,
        accuracy: 10,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isTrue,
    );
  });

  test('a one-sample hop to the next street does not move the pin', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    // About 60 m, still inside the speed limit, but only one sample.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.60054,
        lng: 121.0,
        accuracy: 12,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
    // Back beside the original pin. The hop is dropped.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 6)),
        lat: 14.60016,
        lng: 121.0,
        accuracy: 10,
        now: t0.add(const Duration(seconds: 6)),
      ),
      isTrue,
    );
  });

  test('a hop that the next sample agrees with is kept', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.60054,
        lng: 121.0,
        accuracy: 12,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
    // About 20 m past that hop, so the bike did move.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 6)),
        lat: 14.60072,
        lng: 121.0,
        accuracy: 12,
        now: t0.add(const Duration(seconds: 6)),
      ),
      isTrue,
    );
  });

  test('a coarse point cannot drag the pin', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: 14.6008,
        lng: 121.0,
        accuracy: 120,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
  });

  test('three accurate readings that agree can catch the pin up', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    const far = 14.61;
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 3)),
        lat: far,
        lng: 121.0,
        accuracy: 10,
        now: t0.add(const Duration(seconds: 3)),
      ),
      isFalse,
    );
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 6)),
        lat: far,
        lng: 121.0,
        accuracy: 10,
        now: t0.add(const Duration(seconds: 6)),
      ),
      isFalse,
    );
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 9)),
        lat: far,
        lng: 121.0,
        accuracy: 10,
        now: t0.add(const Duration(seconds: 9)),
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

  test('a fresh fix after a long lock replaces the old pin', () {
    final gate = RideFixGate();
    final t0 = DateTime.utc(2026, 10, 1, 12);
    expect(
      gate.accept(
        sampleTime: t0,
        lat: 14.6,
        lng: 121.0,
        accuracy: 8,
        now: t0,
      ),
      isTrue,
    );
    final later = t0.add(const Duration(minutes: 2));
    // An old satellite time must not teleport the pin, even after the gap.
    expect(
      gate.accept(
        sampleTime: t0.add(const Duration(seconds: 5)),
        lat: 14.6036,
        lng: 121.0,
        accuracy: 12,
        now: later,
      ),
      isFalse,
    );
    // About 400 m north, stamped now. This is where the bike is.
    expect(
      gate.accept(
        sampleTime: later,
        lat: 14.6036,
        lng: 121.0,
        accuracy: 12,
        now: later,
      ),
      isTrue,
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
