import 'package:flutter/material.dart';

/// Soft gradient + abstract shapes for user-area tabs (scan landing, profile, etc.).
class UserPortalBackdrop extends StatelessWidget {
  const UserPortalBackdrop({super.key, required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final surface = colorScheme.surface;
    final primary = colorScheme.primary;
    final pContainer = colorScheme.primaryContainer;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(surface, pContainer, 0.22) ?? surface,
                  surface,
                  Color.lerp(surface, primary, 0.045) ?? surface,
                ],
                stops: const [0.0, 0.52, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          top: -100,
          right: -80,
          child: _RadialWash(
            size: 320,
            inner: primary.withValues(alpha: 0.14),
            outer: primary.withValues(alpha: 0),
          ),
        ),
        Positioned(
          top: 120,
          left: -120,
          child: _RadialWash(
            size: 340,
            inner: pContainer.withValues(alpha: 0.55),
            outer: pContainer.withValues(alpha: 0),
          ),
        ),
        Positioned(
          bottom: -60,
          right: -40,
          child: _RadialWash(
            size: 260,
            inner: primary.withValues(alpha: 0.08),
            outer: primary.withValues(alpha: 0),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _PortalGridPainter(
              color: colorScheme.outlineVariant.withValues(alpha: 0.12),
            ),
          ),
        ),
      ],
    );
  }
}

class _RadialWash extends StatelessWidget {
  const _RadialWash({
    required this.size,
    required this.inner,
    required this.outer,
  });

  final double size;
  final Color inner;
  final Color outer;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [inner, outer]),
        ),
      ),
    );
  }
}

class _PortalGridPainter extends CustomPainter {
  _PortalGridPainter({required this.color});

  final Color color;
  static const _step = 28.0;
  static const _dotRadius = 0.9;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 0; x < size.width + _step; x += _step) {
      for (double y = 0; y < size.height + _step; y += _step) {
        canvas.drawCircle(Offset(x, y), _dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PortalGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }

  @override
  bool? hitTest(Offset position) => false;
}

/// Standard shell for Scan / Active / History / Profile: backdrop + blended app bar.
class UserPortalScaffold extends StatelessWidget {
  const UserPortalScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Color.lerp(cs.surface, cs.primaryContainer, 0.08),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: actions,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: UserPortalBackdrop(colorScheme: cs)),
          body,
        ],
      ),
    );
  }
}

/// Frosted list group: matches scan / profile cards.
class PolishedSectionCard extends StatelessWidget {
  const PolishedSectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.82),
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: child,
        ),
      ),
    );
  }
}

/// Section label above grouped content.
class PortalSectionLabel extends StatelessWidget {
  const PortalSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
