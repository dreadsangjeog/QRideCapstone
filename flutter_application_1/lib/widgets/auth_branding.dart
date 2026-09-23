import 'package:flutter/material.dart';

import '../theme/brand.dart';
import 'qride_brand.dart';

/// Login / marketing gradient behind [SafeArea] content.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return QrideBrandBackdrop(child: child);
  }
}

/// Launcher bike icon + “QRide” title + Scan / Ride / Return tagline.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        const SizedBox(height: 12),
        const QrideBikeMark(size: 88),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              QrideBrand.accentSoft,
              QrideBrand.accent,
              QrideBrand.accentDeep,
            ],
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
            const _TagDot(color: QrideBrand.accentSoft),
            const SizedBox(width: 6),
            Text(
              'Scan',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 10),
            const _TagDot(color: QrideBrand.accent),
            const SizedBox(width: 6),
            Text(
              'Ride',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 10),
            const _TagDot(color: QrideBrand.accentDeep),
            const SizedBox(width: 6),
            Text(
              'Return',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
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
