import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

import '../config/map_config.dart';

/// Campus map in a quiet Google-style palette.
///
/// Place names stay on the map at every zoom. CARTO's own label tiles draw
/// countries and cities while zoomed out, then add street names as the view
/// gets closer. The base layer keeps blue water, green parks and hills, light
/// cool grey for most roads, and light slate blue for the main highways.
List<Widget> qrideStreetTiles() {
  return [
    TileLayer(
      urlTemplate: _cartoTemplate('voyager_nolabels'),
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.qride.demo',
      maxZoom: 20,
      tileProvider: _mutedBasemap,
    ),
    _cartoLayer('voyager_only_labels'),
  ];
}

/// One client for every map screen. [TileLayer] disposes its provider when the
/// screen closes, and closing this client would break the next map.
final _MutedBasemapProvider _mutedBasemap = _MutedBasemapProvider();

TileLayer _cartoLayer(String style) {
  return TileLayer(
    urlTemplate: _cartoTemplate(style),
    subdomains: const ['a', 'b', 'c', 'd'],
    userAgentPackageName: 'com.qride.demo',
    maxZoom: 20,
  );
}

String _cartoTemplate(String style) {
  final key = MapConfig.effectiveCartoKey;
  final keyed = key.isEmpty ? '' : '?key=$key';
  return 'https://{s}.basemaps.cartocdn.com/rastertiles/$style/{z}/{x}/{y}{r}.png$keyed';
}

/// Recolors one Voyager pixel toward the muted Google palette.
@visibleForTesting
(int, int, int) muteBasemapPixel(int r, int g, int b) {
  // Rivers and the bay. Voyager water is only slightly bluer than the land.
  if (b > r + 8 && b + 8 >= g && g > 150) {
    final delta = b - r - 8;
    final strength = delta >= 18 ? 1000 : delta * 1000 ~/ 18;
    final amount = 550 + 400 * strength ~/ 1000;
    return (_mix(r, 164, amount), _mix(g, 206, amount), _mix(b, 226, amount));
  }
  // Parks, hills, and mountains. Cream roads have more red than green.
  if (g >= r + 3 && g + 6 >= b && r < 250 && b > 145) {
    final delta = g - r;
    final strength = delta >= 12 ? 1000 : delta * 1000 ~/ 12;
    final amount = 420 + 500 * strength ~/ 1000;
    return (_mix(r, 176, amount), _mix(g, 210, amount), _mix(b, 162, amount));
  }
  // Yellow highways become light slate blue. The wider cream roads stay grey.
  if (r > 232 && g > 185 && (r - b) > 36) {
    final warmth = r - b;
    if (warmth >= 56) {
      final delta = warmth - 40;
      final strength = delta >= 28 ? 1000 : delta * 1000 ~/ 28;
      final amount = 620 + 300 * strength ~/ 1000;
      return (
        _mix(r, 168, amount),
        _mix(g, 192, amount),
        _mix(b, 214, amount),
      );
    }
    return (_mix(r, 206, 720), _mix(g, 210, 720), _mix(b, 216, 720));
  }
  // Minor streets are already near white. Cool them without darkening them.
  if (r > 246 && g > 246 && b > 242) {
    return (_mix(r, 232, 550), _mix(g, 235, 550), _mix(b, 238, 550));
  }
  final avg1000 = (r + g + b) * 1000 ~/ 3;
  return (
    _land(r, 420, avg1000, 380, 46000),
    _land(g, 400, avg1000, 380, 52000),
    _land(b, 340, avg1000, 400, 64000),
  );
}

int _mix(int src, int target, int amount1000) {
  return src + (target - src) * amount1000 ~/ 1000;
}

int _land(int channel, int weight, int avg1000, int avgWeight, int bias) {
  final mixed = (channel * weight + avg1000 * avgWeight ~/ 1000 + bias) ~/ 1000;
  if (mixed < 0) return 0;
  if (mixed > 255) return 255;
  return mixed;
}

class _MutedBasemapProvider extends TileProvider {
  _MutedBasemapProvider() : super();

  final BaseClient _httpClient = RetryClient(Client());

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _MutedTileImage(
      getTileUrl(coordinates, options),
      headers,
      _httpClient,
    );
  }

  @override
  void dispose() {}
}

@immutable
class _MutedTileImage extends ImageProvider<_MutedTileImage> {
  const _MutedTileImage(this.url, this.headers, this.client);

  final String url;
  final Map<String, String> headers;
  final BaseClient client;

  @override
  ImageStreamCompleter loadImage(
    _MutedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _load(_MutedTileImage key, ImageDecoderCallback decode) async {
    try {
      final bytes = await key.client.readBytes(
        Uri.parse(key.url),
        headers: key.headers,
      );
      return _decodeMuted(bytes, decode);
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  SynchronousFuture<_MutedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_MutedTileImage>(this);
  }

  @override
  bool operator ==(Object other) =>
      other is _MutedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

Future<ui.Codec> _decodeMuted(
  Uint8List bytes,
  ImageDecoderCallback decode,
) async {
  try {
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width;
    final height = image.height;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null || data.lengthInBytes != width * height * 4) {
      image.dispose();
      codec.dispose();
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    }
    final pixels = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    image.dispose();
    codec.dispose();
    for (var i = 0; i < pixels.length; i += 4) {
      final muted = muteBasemapPixel(pixels[i], pixels[i + 1], pixels[i + 2]);
      pixels[i] = muted.$1;
      pixels[i + 1] = muted.$2;
      pixels[i + 2] = muted.$3;
    }
    final png = await _pngFromRgba(pixels, width, height);
    return decode(await ui.ImmutableBuffer.fromUint8List(png));
  } catch (_) {
    // A failed recolor still shows the original tile instead of a blank square.
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }
}

Future<Uint8List> _pngFromRgba(Uint8List rgba, int width, int height) {
  final done = Completer<Uint8List>();
  ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, (
    ui.Image image,
  ) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null || done.isCompleted) return;
      done.complete(
        Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    } catch (error, stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    }
  });
  return done.future;
}

/// Attribution overlay (hidden — tiles still use OSM/CARTO under the hood).
Widget qrideMapAttribution() => const SizedBox.shrink();
