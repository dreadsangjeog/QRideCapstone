import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class KycIdStillCheck {
  const KycIdStillCheck({
    required this.hasPortrait,
    required this.hasText,
    required this.isSharp,
    required this.tooDark,
    required this.glare,
    required this.hint,
  });

  final bool hasPortrait;
  final bool hasText;
  final bool isSharp;
  final bool tooDark;
  final bool glare;
  final String hint;

  bool get ok => hasPortrait && hasText && !tooDark;
}

/// Confirms the still is a real, readable ID — not a blurry table or a selfie.
class KycIdQuality {
  static Future<KycIdStillCheck> reviewStill(Uint8List jpeg) async {
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}/kyc_id_check_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(jpeg, flush: true);

    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.03,
      ),
    );
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final input = InputImage.fromFilePath(file.path);
      final faces = await detector.processImage(input);
      final text = await recognizer.processImage(input);
      final pixels = await _sample(jpeg);
      final frame = await _jpegSize(jpeg);

      final letters = _lettersOf(text.text);
      final words = _wordsOf(text.text);
      final hasText = letters >= 18 && words >= 3;

      final portrait = _idPortrait(faces, frame);
      final dark = pixels.mean < 42;
      final glare = pixels.hotFrac > 0.16;
      final sharp = pixels.sharpness >= 14 && pixels.contrast >= 16;

      final hint = !portrait
          ? 'Hold closer so the printed face on the ID is sharp and easy to see.'
          : !hasText
              ? 'The name on the ID is not readable. Hold closer and avoid blur.'
              : dark
                  ? 'Too dark. Move to brighter light.'
                  : glare
                      ? 'Too much glare. Tilt the card slightly.'
                      : !sharp
                          ? 'The photo is not sharp enough. Hold still, then try again.'
                          : 'ID looks clear.';

      return KycIdStillCheck(
        hasPortrait: portrait,
        hasText: hasText,
        isSharp: sharp,
        tooDark: dark,
        glare: glare,
        hint: hint,
      );
    } finally {
      await detector.close();
      await recognizer.close();
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static bool looksLikeReadableText(String raw) {
    return _lettersOf(raw) >= 14 && _wordsOf(raw) >= 3;
  }

  static int _lettersOf(String raw) {
    return raw.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '').length;
  }

  static int _wordsOf(String raw) {
    return raw
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .length;
  }

  /// An ID portrait is a small printed face, not a live selfie filling the frame.
  static bool _idPortrait(List<Face> faces, ui.Size size) {
    if (size.width <= 0 || size.height <= 0) return false;
    final printed = faces.where((f) {
      final box = f.boundingBox;
      if (box.width < 22 || box.height < 26) return false;
      final fracH = box.height / size.height;
      final fracW = box.width / size.width;
      if (fracH < 0.04 || fracH > 0.62) return false;
      if (fracW < 0.03 || fracW > 0.52) return false;
      return true;
    }).toList();
    return printed.isNotEmpty;
  }

  static Future<_PixelStats> _sample(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg, targetWidth: 360);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width;
    final h = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (data == null) {
      return const _PixelStats(
        mean: 128,
        contrast: 0,
        sharpness: 0,
        hotFrac: 0,
      );
    }
    final bytes = data.buffer.asUint8List();
    var sum = 0;
    var hot = 0;
    var n = 0;
    final lumas = <int>[];
    for (var y = 0; y < h; y += 2) {
      for (var x = 0; x < w; x += 2) {
        final i = (y * w + x) * 4;
        final yv = ((bytes[i] * 299) + (bytes[i + 1] * 587) + (bytes[i + 2] * 114)) ~/
            1000;
        lumas.add(yv);
        sum += yv;
        if (yv > 246) hot++;
        n++;
      }
    }
    final mean = n == 0 ? 128.0 : sum / n;
    var varSum = 0.0;
    for (final yv in lumas) {
      final d = yv - mean;
      varSum += d * d;
    }
    final contrast = n == 0 ? 0.0 : math.sqrt(varSum / n);

    var lap = 0.0;
    var ln = 0;
    int luma(int x, int y) {
      final i = (y * w + x) * 4;
      return ((bytes[i] * 299) + (bytes[i + 1] * 587) + (bytes[i + 2] * 114)) ~/
          1000;
    }

    for (var y = 2; y < h - 2; y += 3) {
      for (var x = 2; x < w - 2; x += 3) {
        final c = luma(x, y);
        final v = (4 * c - luma(x - 1, y) - luma(x + 1, y) - luma(x, y - 1) - luma(x, y + 1))
            .abs();
        lap += v;
        ln++;
      }
    }

    return _PixelStats(
      mean: mean,
      contrast: contrast,
      sharpness: ln == 0 ? 0 : lap / ln,
      hotFrac: n == 0 ? 0 : hot / n,
    );
  }

  static Future<ui.Size> _jpegSize(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    final frame = await codec.getNextFrame();
    final size = ui.Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    return size;
  }
}

class _PixelStats {
  const _PixelStats({
    required this.mean,
    required this.contrast,
    required this.sharpness,
    required this.hotFrac,
  });

  final double mean;
  final double contrast;
  final double sharpness;
  final double hotFrac;
}
