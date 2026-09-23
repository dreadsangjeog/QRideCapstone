/// Free CARTO Voyager key — request at https://carto.com/basemaps/apikey/
/// (no CARTO account needed). They email the key; paste it here.
///
/// Without this key, Carto stamps **API KEY REQUIRED** on every tile.
class MapConfig {
  static const cartoBasemapKey = 'cb1_30gy_1_411ee36561af279d4ef27ef6';

  static String get effectiveCartoKey => cartoBasemapKey.trim();

  static bool get hasCartoKey => effectiveCartoKey.isNotEmpty;
}
