import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../theme/theme_controller.dart';

/// Layered wash behind admin chrome so liquid-glass panels have color to
/// refract — light: cool sky + lilac, dark: deep navy + cobalt.
class AdminGlassScene extends StatelessWidget {
  const AdminGlassScene({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF070B14),
                  Color(0xFF0B1220),
                  Color(0xFF10263F),
                ]
              : const [
                  Color(0xFFB9DBFF),
                  Color(0xFFF4F8FC),
                  Color(0xFFE4D7FF),
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -140,
            right: -80,
            child: _Orb(
              size: 420,
              color: QrideBrand.accent.withValues(alpha: isDark ? 0.28 : 0.32),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -100,
            child: _Orb(
              size: 380,
              color: (isDark ? const Color(0xFF7C5CFF) : const Color(0xFFB388FF))
                  .withValues(alpha: isDark ? 0.22 : 0.26),
            ),
          ),
          Positioned(
            top: 220,
            left: isDark ? -40 : 80,
            child: _Orb(
              size: 220,
              color: const Color(0xFF5AC8FA)
                  .withValues(alpha: isDark ? 0.16 : 0.20),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});

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

/// iOS-style liquid glass plate. Works in light and dark.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.radius = 22,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = tint ??
        (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.48));
    final rim = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.82);
    final shine = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.72);

    final plate = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: rim, width: 1.1),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 28,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(radius),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [shine, shine.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: padding ?? const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );

    final shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: plate,
    );

    if (onTap == null) return shadowed;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: plate,
        ),
      ),
    );
  }
}

/// Cycles light ↔ dark. Saved by [setThemeMode].
class AdminThemeToggle extends StatelessWidget {
  const AdminThemeToggle({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return IconButton(
          tooltip: isDark ? 'Light mode' : 'Dark mode',
          onPressed: () {
            setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
          },
          icon: Icon(
            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            color: color,
          ),
        );
      },
    );
  }
}
