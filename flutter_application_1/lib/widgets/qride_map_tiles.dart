import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/map_config.dart';

/// CARTO Voyager (the cleaner campus-style map). Needs [MapConfig.cartoBasemapKey].
TileLayer qrideStreetTiles() {
  final key = MapConfig.effectiveCartoKey;
  final keyed = key.isEmpty ? '' : '?key=$key';
  return TileLayer(
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png$keyed',
    subdomains: const ['a', 'b', 'c', 'd'],
    userAgentPackageName: 'com.qride.demo',
    maxZoom: 20,
  );
}

/// Attribution overlay (hidden — tiles still use OSM/CARTO under the hood).
Widget qrideMapAttribution() => const SizedBox.shrink();

