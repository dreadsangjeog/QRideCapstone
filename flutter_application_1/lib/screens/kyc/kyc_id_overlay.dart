import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ISO ID-1 card (credit-card) proportions.
const kKycIdAspect = 1.5858;

enum KycIdLayout { horizontal, vertical }

class KycIdEdges {
  const KycIdEdges({
    this.top = false,
    this.right = false,
    this.bottom = false,
    this.left = false,
  });

  final bool top;
  final bool right;
  final bool bottom;
  final bool left;

  bool get all => top && right && bottom && left;
  int get count =>
      (top ? 1 : 0) + (right ? 1 : 0) + (bottom ? 1 : 0) + (left ? 1 : 0);
}

class KycIdChecks {
  const KycIdChecks({
    this.frame = false,
    this.portrait = false,
    this.text = false,
    this.sharp = false,
  });

  final bool frame;
  final bool portrait;
  final bool text;
  final bool sharp;

  bool get ready => portrait && text;
  int get count =>
      (frame ? 1 : 0) + (portrait ? 1 : 0) + (text ? 1 : 0) + (sharp ? 1 : 0);
}

class KycIdGuide {
  static Rect cardOn(
    Size size, {
    KycIdLayout layout = KycIdLayout.horizontal,
  }) {
    if (layout == KycIdLayout.vertical) {
      final maxW = size.width * 0.64;
      final maxH = size.height * 0.54;
      var height = maxH;
      var width = height / kKycIdAspect;
      if (width > maxW) {
        width = maxW;
        height = width * kKycIdAspect;
      }
      return Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.40),
        width: width,
        height: height,
      );
    }

    final maxW = size.width * 0.88;
    final maxH = size.height * 0.38;
    var width = maxW;
    var height = width / kKycIdAspect;
    if (height > maxH) {
      height = maxH;
      width = height * kKycIdAspect;
    }
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: width,
      height: height,
    );
  }
}

class KycIdFrame extends StatelessWidget {
  const KycIdFrame({
    super.key,
    required this.edges,
    required this.holdProgress,
    this.layout = KycIdLayout.horizontal,
    this.locked = false,
  });

  final KycIdEdges edges;
  final double holdProgress;
  final KycIdLayout layout;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _KycIdFramePainter(
        edges: edges,
        holdProgress: holdProgress.clamp(0.0, 1.0),
        layout: layout,
        locked: locked,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _KycIdFramePainter extends CustomPainter {
  _KycIdFramePainter({
    required this.edges,
    required this.holdProgress,
    required this.layout,
    required this.locked,
  });

  final KycIdEdges edges;
  final double holdProgress;
  final KycIdLayout layout;
  final bool locked;

  static const _idle = Color(0x55FFFFFF);
  static const _hot = Color(0xFF0A84FF);
  static const _done = Color(0xFF34C759);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) return;
    final card = KycIdGuide.cardOn(size, layout: layout);
    final radius = Radius.circular(16);

    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(card, radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(card, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white24,
    );

    final arm = math.min(card.width, card.height) * 0.18;
    _corner(canvas, card.topLeft, arm, true, true, edges.left && edges.top);
    _corner(canvas, card.topRight, arm, false, true, edges.right && edges.top);
    _corner(
      canvas,
      card.bottomLeft,
      arm,
      true,
      false,
      edges.left && edges.bottom,
    );
    _corner(
      canvas,
      card.bottomRight,
      arm,
      false,
      false,
      edges.right && edges.bottom,
    );

    if (holdProgress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(card.inflate(12), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = (locked ? _done : _hot).withValues(alpha: 0.95),
      );
    }
  }

  void _corner(
    Canvas canvas,
    Offset origin,
    double arm,
    bool fromLeft,
    bool fromTop,
    bool on,
  ) {
    final paint = Paint()
      ..color = locked ? _done : (on ? _hot : _idle)
      ..strokeWidth = on || locked ? 6 : 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dx = fromLeft ? arm : -arm;
    final dy = fromTop ? arm : -arm;
    canvas.drawLine(origin, origin.translate(dx, 0), paint);
    canvas.drawLine(origin, origin.translate(0, dy), paint);
  }

  @override
  bool shouldRepaint(_KycIdFramePainter old) {
    return old.edges.top != edges.top ||
        old.edges.right != edges.right ||
        old.edges.bottom != edges.bottom ||
        old.edges.left != edges.left ||
        old.holdProgress != holdProgress ||
        old.layout != layout ||
        old.locked != locked;
  }
}
