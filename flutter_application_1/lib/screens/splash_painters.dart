part of 'splash_screen.dart';

/// Very subtle motion — low contrast so it doesn’t fight the hero.
class _OrbitingDots extends CustomPainter {
  _OrbitingDots({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 24;

    for (var i = 0; i < 3; i++) {
      final angle = t * 2 * math.pi + i * (2 * math.pi / 3);
      final pos = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final dotRadius = 3.2 - i * 0.5;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.35 - i * 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitingDots old) =>
      old.t != t || old.color != color;
}
