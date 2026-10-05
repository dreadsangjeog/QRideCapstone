import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// PNG sticker: the scannable code and the bike code text only.
Future<Uint8List> renderBikeQrPng(String code) async {
  const qrSize = 720.0;
  const pad = 64.0;
  final painter = QrPainter(
    data: code,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  );

  final textPainter = TextPainter(
    text: TextSpan(
      text: code,
      style: const TextStyle(
        color: Color(0xFF111111),
        fontSize: 56,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final width = math.max(qrSize + pad * 2, textPainter.width + pad * 2);
  final height = pad + qrSize + 36 + textPainter.height + pad;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.save();
  canvas.translate((width - qrSize) / 2, pad);
  painter.paint(canvas, const Size(qrSize, qrSize));
  canvas.restore();
  textPainter.paint(
    canvas,
    Offset((width - textPainter.width) / 2, pad + qrSize + 36),
  );

  final image = await recorder.endRecording().toImage(
    width.ceil(),
    height.ceil(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Could not build the QR image.');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
