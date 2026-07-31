import 'package:flutter/material.dart';

/// Login / marketing gradient behind [SafeArea] content.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.12),
            cs.surface,
            cs.secondary.withValues(alpha: 0.10),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Bike icon + “QRide” title + Scan / Ride / Return tagline.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  static const Color brandGradientStart = Color(0xFF4A90E2);
  static const Color brandGradientMid = Color(0xFF007AFF);
  static const Color brandGradientEnd = Color(0xFF38B6FF);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [brandGradientStart, brandGradientMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: brandGradientMid.withValues(alpha: 0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 9),
                ),
              ],
            ),
            child: const Icon(Icons.directions_bike_rounded,
                color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [brandGradientStart, brandGradientMid, brandGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            'QRide',
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TagDot(color: brandGradientStart),
            const SizedBox(width: 6),
            Text('Scan',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                )),
            const SizedBox(width: 10),
            _TagDot(color: brandGradientMid),
            const SizedBox(width: 6),
            Text('Ride',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                )),
            const SizedBox(width: 10),
            _TagDot(color: brandGradientEnd),
            const SizedBox(width: 6),
            Text('Return',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                )),
          ],
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

class _TagDot extends StatelessWidget {
  const _TagDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
