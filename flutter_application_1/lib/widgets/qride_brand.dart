import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// Shared backdrop for splash, auth, and rider home — light airy blue.
class QrideBrandBackdrop extends StatelessWidget {
  const QrideBrandBackdrop({
    super.key,
    this.child,
    this.dark = false,
  });

  final Widget? child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = dark || cs.brightness == Brightness.dark;

    final colors = isDark
        ? const [
            Color(0xFF0B1220),
            Color(0xFF101827),
            Color(0xFF152033),
          ]
        : const [
            Color(0xFFEAF4FF),
            QrideBrand.mist,
            Color(0xFFFFFFFF),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _Glow(
              size: 340,
              color: QrideBrand.accent.withValues(alpha: isDark ? 0.22 : 0.10),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -90,
            child: _Glow(
              size: 300,
              color:
                  QrideBrand.accentSoft.withValues(alpha: isDark ? 0.16 : 0.10),
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Launcher-style bike mark used on splash / home / auth.
/// Always the blue bike — never the purple/black app icon.
class QrideBikeMark extends StatelessWidget {
  const QrideBikeMark({
    super.key,
    this.size = 88,
    this.showPlate = true,
  });

  final double size;
  final bool showPlate;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mark = ColorFiltered(
      colorFilter: const ColorFilter.mode(
        QrideBrand.accent,
        BlendMode.srcIn,
      ),
      child: Image.asset(
        QrideBrand.bikeLight,
        width: size * 0.62,
        height: size * 0.62,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
      ),
    );

    if (!showPlate) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? QrideBrand.night : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: QrideBrand.accent.withValues(alpha: isDark ? 0.28 : 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: QrideBrand.accent.withValues(alpha: isDark ? 0.28 : 0.18),
            blurRadius: isDark ? 24 : 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: mark,
    );
  }
}

