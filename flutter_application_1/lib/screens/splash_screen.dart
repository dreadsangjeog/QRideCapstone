import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../widgets/qride_brand.dart';

part 'splash_painters.dart';

/// Cold-start splash — light blue chrome + launcher bike mark.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final Animation<double> _logoOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
  );

  late final Animation<double> _logoScale = Tween<double>(begin: 0.92, end: 1.0)
      .animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
    ),
  );

  late final Animation<Offset> _logoSlide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.50, curve: Curves.easeOutCubic),
    ),
  );

  late final Animation<double> _tagOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.35, 0.72, curve: Curves.easeOut),
  );

  late final Animation<Offset> _tagSlide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.35, 0.72, curve: Curves.easeOutCubic),
    ),
  );

  late final Animation<double> _progressOpacity = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.60, 0.85, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _pulse.forward();
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wordStyle = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.05,
      color: isDark ? Colors.white : QrideBrand.accentDeep,
    );
    final tagStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: isDark
          ? QrideBrand.accentSoft.withValues(alpha: 0.9)
          : QrideBrand.accentDeep.withValues(alpha: 0.70),
    );
    final ringDot = isDark
        ? QrideBrand.accentSoft.withValues(alpha: 0.55)
        : QrideBrand.accent.withValues(alpha: 0.40);

    return Scaffold(
      body: QrideBrandBackdrop(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _pulse]),
            builder: (context, _) {
              final pulseT = _pulse.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: Container(
                        width: 300 + 40 * pulseT,
                        height: 300 + 40 * pulseT,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              QrideBrand.accent
                                  .withValues(alpha: isDark ? 0.22 : 0.12),
                              QrideBrand.accentSoft
                                  .withValues(alpha: isDark ? 0.10 : 0.06),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.35 + 0.1 * pulseT, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: 340,
                      height: 340,
                      child: FadeTransition(
                        opacity: _tagOpacity,
                        child: CustomPaint(
                          painter: _OrbitingDots(
                            t: _intro.value,
                            color: ringDot,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: SlideTransition(
                              position: _logoSlide,
                              child: FadeTransition(
                                opacity: _logoOpacity,
                                child: ScaleTransition(
                                  scale: _logoScale,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const QrideBikeMark(size: 108),
                                      const SizedBox(height: 22),
                                      Text('QRide', style: wordStyle),
                                      const SizedBox(height: 16),
                                      SlideTransition(
                                        position: _tagSlide,
                                        child: FadeTransition(
                                          opacity: _tagOpacity,
                                          child: Text(
                                            'Scan  ·  Ride  ·  Return',
                                            style: tagStyle,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      FadeTransition(
                        opacity: _progressOpacity,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 36),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 128,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    minHeight: 4,
                                    backgroundColor: (isDark
                                            ? Colors.white
                                            : QrideBrand.accentDeep)
                                        .withValues(alpha: 0.10),
                                    valueColor: const AlwaysStoppedAnimation(
                                      QrideBrand.accent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'LOADING',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.8,
                                  color: (isDark
                                          ? Colors.white
                                          : QrideBrand.accentDeep)
                                      .withValues(alpha: 0.38),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
