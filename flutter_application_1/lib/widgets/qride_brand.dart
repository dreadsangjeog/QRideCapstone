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

/// The QRide bike on its rounded plate, as on the launcher icon.
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

/// "QRide" in the brand gradient.
class QrideWordmark extends StatelessWidget {
  const QrideWordmark({super.key, this.fontSize = 36});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: isDark
            ? const [Color(0xFFB9DCFF), Color(0xFF4DA3FF), QrideBrand.accent]
            : const [
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
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -fontSize / 30,
          height: 1.1,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Scan · Ride · Return, with a brand dot before each word.
class QrideTagline extends StatelessWidget {
  const QrideTagline({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    Widget word(String text, Color dot) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(text, style: style),
          ],
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        word('Scan', QrideBrand.accentSoft),
        const SizedBox(width: 12),
        word('Ride', QrideBrand.accent),
        const SizedBox(width: 12),
        word('Return', QrideBrand.accentDeep),
      ],
    );
  }
}

/// Mark, wordmark and tagline over the brand backdrop, shared by the splash
/// and every startup state that follows it.
///
/// With [lift] and [reveal] at 0 the mark sits alone in the middle of the
/// screen, exactly where Android's launch screen draws it.
class QrideLaunchLayout extends StatelessWidget {
  const QrideLaunchLayout({
    super.key,
    this.lift = 1,
    this.reveal = 1,
    this.glow = 1,
    this.footer,
  });

  /// Size of the mark. Android's launch screen draws the same plate.
  static const double markSize = 112;

  static const double _liftBy = 52;

  final double lift;
  final double reveal;
  final double glow;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: isDark ? QrideBrand.night : QrideBrand.mist,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: glow.clamp(0.0, 1.0), child: const QrideBrandBackdrop()),
          LayoutBuilder(
            builder: (context, box) {
              final markTop = box.maxHeight / 2 - markSize / 2 - _liftBy * lift;
              return Stack(
                children: [
                  Positioned(
                    top: markTop,
                    left: 0,
                    right: 0,
                    child: const Center(child: QrideBikeMark(size: markSize)),
                  ),
                  Positioned(
                    top: markTop + markSize + 22 + 14 * (1 - reveal),
                    left: 24,
                    right: 24,
                    child: Opacity(
                      opacity: reveal.clamp(0.0, 1.0),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrideWordmark(fontSize: 42),
                          SizedBox(height: 10),
                          QrideTagline(),
                        ],
                      ),
                    ),
                  ),
                  if (footer != null)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 40 + bottomInset,
                      child: Center(child: footer),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Small brand-blue spinner used under the launch layout.
class QrideLaunchSpinner extends StatelessWidget {
  const QrideLaunchSpinner({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        strokeCap: StrokeCap.round,
        color: QrideBrand.accent,
      ),
    );
  }
}

/// Shown while the app works out where a signed-in user belongs. Looks like
/// the end of the splash, so the hand-off is invisible.
class QrideLoadingView extends StatelessWidget {
  const QrideLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        label: 'Loading QRide',
        child: const QrideLaunchLayout(footer: QrideLaunchSpinner()),
      ),
    );
  }
}

/// Startup failure in the same frame as the splash, with a way forward.
class QrideStartupProblem extends StatelessWidget {
  const QrideStartupProblem({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.onSignOut,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (onRetry != null || onSignOut != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (onSignOut != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onSignOut,
                        child: const Text('Log out'),
                      ),
                    ),
                  if (onSignOut != null && onRetry != null)
                    const SizedBox(width: 10),
                  if (onRetry != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onRetry,
                        child: const Text('Try again'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    return Scaffold(
      body: QrideBrandBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: QrideBikeMark(size: 88)),
                    const SizedBox(height: 16),
                    const QrideWordmark(fontSize: 34),
                    const SizedBox(height: 28),
                    card,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
