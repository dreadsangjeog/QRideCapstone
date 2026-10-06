import 'package:flutter_application_1/widgets/qride_map_tiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('highways go slate, other roads stay grey, water and land keep color', () {
    final highway = muteBasemapPixel(255, 234, 189);
    expect(highway.$3, greaterThan(highway.$1));
    expect(highway.$3, greaterThan(highway.$2 - 5));

    final creamRoad = muteBasemapPixel(251, 236, 202);
    expect((creamRoad.$1 - creamRoad.$2).abs(), lessThan(16));
    expect((creamRoad.$2 - creamRoad.$3).abs(), lessThan(16));
    expect(creamRoad.$1, greaterThan(180));

    final street = muteBasemapPixel(252, 252, 252);
    expect(street.$1, greaterThan(230));
    expect((street.$1 - street.$3).abs(), lessThan(10));

    final water = muteBasemapPixel(206, 229, 232);
    expect(water.$3, greaterThan(water.$2));
    expect(water.$2, greaterThan(water.$1));

    final park = muteBasemapPixel(229, 238, 217);
    expect(park.$2, greaterThan(park.$1));
    expect(park.$2, greaterThan(park.$3));
  });
}
