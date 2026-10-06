import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// Google-style navigation arrow (0° = north).
class HeadingChevron extends StatelessWidget {
  const HeadingChevron({
    super.key,
    required this.headingDeg,
    this.color = const Color(0xFF1A73E8),
    this.size = 22,
  });

  final double headingDeg;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: headingDeg * math.pi / 180,
      child: Icon(
        Icons.navigation_rounded,
        size: size,
        color: color,
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 4),
          Shadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

/// Google / Apple Maps style blue puck: circle + heading fan.
class MapsHeadingPuck extends StatelessWidget {
  const MapsHeadingPuck({
    super.key,
    required this.headingDeg,
    this.size = 56,
    this.color = const Color(0xFF1A73E8),
  });

  final double headingDeg;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: headingDeg * math.pi / 180,
        child: CustomPaint(
          painter: _MapsPuckPainter(color: color),
        ),
      ),
    );
  }
}

class _MapsPuckPainter extends CustomPainter {
  _MapsPuckPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.16;

    final fan = Path()
      ..moveTo(c.dx, c.dy - size.height * 0.46)
      ..quadraticBezierTo(
        c.dx + size.width * 0.22,
        c.dy - size.height * 0.08,
        c.dx + r * 0.15,
        c.dy - r,
      )
      ..lineTo(c.dx - r * 0.15, c.dy - r)
      ..quadraticBezierTo(
        c.dx - size.width * 0.22,
        c.dy - size.height * 0.08,
        c.dx,
        c.dy - size.height * 0.46,
      )
      ..close();

    canvas.drawPath(
      fan,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.42),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.48)),
    );

    canvas.drawCircle(
      c,
      r + 6,
      Paint()..color = color.withValues(alpha: 0.16),
    );
    canvas.drawCircle(c, r + 3.4, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MapsPuckPainter old) => old.color != color;
}

/// Smoothly eases [target] so markers slide instead of jumping.
class SmoothLatLng {
  SmoothLatLng(this.current) : target = current;

  LatLng current;
  LatLng target;
  double heading = 0;
  double headingTarget = 0;

  void setTarget(LatLng next, double? headingDeg) {
    target = next;
    if (headingDeg != null && headingDeg >= 0 && headingDeg <= 360) {
      headingTarget = headingDeg;
    }
  }

  /// Places the pin on [next] with no travel from the previous point.
  ///
  /// Used for the first real fix when the app opens. Easing from the
  /// placeholder made the map slide across the city.
  void snapTo(LatLng next, double? headingDeg) {
    current = next;
    target = next;
    if (headingDeg != null && headingDeg >= 0 && headingDeg <= 360) {
      heading = headingDeg;
      headingTarget = headingDeg;
    }
  }

  /// Returns true if the displayed pose moved.
  bool tick({double follow = 0.34}) {
    final dLat = target.latitude - current.latitude;
    final dLng = target.longitude - current.longitude;
    var dHead = headingTarget - heading;
    while (dHead > 180) {
      dHead -= 360;
    }
    while (dHead < -180) {
      dHead += 360;
    }
    final moved = dLat.abs() > 1e-8 || dLng.abs() > 1e-8 || dHead.abs() > 0.4;
    if (!moved) {
      current = target;
      heading = headingTarget;
      return false;
    }
    // Ease every step. A large GPS glitch used to cover most of the gap in
    // one frame, which looked like the pin teleporting.
    final jumpM = Distance().as(
      LengthUnit.Meter,
      current,
      target,
    );
    final capped = jumpM <= 4 ? follow : (4 / jumpM);
    final factor = capped < follow ? capped : follow;
    current = LatLng(
      current.latitude + dLat * factor,
      current.longitude + dLng * factor,
    );
    heading = (heading + dHead * factor) % 360;
    if (heading < 0) heading += 360;
    return true;
  }
}
