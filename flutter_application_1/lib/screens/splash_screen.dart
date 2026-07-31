import 'dart:math' as math;

import 'package:flutter/material.dart';
part 'splash_painters.dart';

/// Cold-start splash: centered hero, readable contrast, transparent logo asset.
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

    // Modern, theme-aware palette (high contrast on the splash itself).
    final bgColors = isDark
        ? const [Color(0xFF0C0A10), Color(0xFF151018), Color(0xFF1B1522)]
        : const [Color(0xFFF3F0FA), Color(0xFFFBFAFE), Color(0xFFFFFFFF)];
    final glow = isDark
        ? const Color(0xFF8B7AD6).withValues(alpha: 0.22)
        : const Color(0xFF6B4E8C).withValues(alpha: 0.12);
    final glowCore = isDark
        ? const Color(0xFFA99AE8).withValues(alpha: 0.14)
        : const Color(0xFF7C5CB5).withValues(alpha: 0.08);

    final wordStyle = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.2,
      height: 1.05,
      color: isDark ? const Color(0xFFF5F2FC) : const Color(0xFF2D1F35),
    );

    final tagStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: isDark
          ? const Color(0xFFB5ADC8).withValues(alpha: 0.95)
          : const Color(0xFF5C5368).withValues(alpha: 0.9),
    );

    final ringDot = isDark
        ? const Color(0xFFC4B8E0).withValues(alpha: 0.55)
        : const Color(0xFF6B5B8C).withValues(alpha: 0.45);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: bgColors,
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _pulse]),
            builder: (context, _) {
              final pulseT = _pulse.value;

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Soft aura (no harsh boxes)
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
                              glowCore,
                              glow,
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/images/qride_logo_mark.png',
                                            height: 76,
                                            filterQuality: FilterQuality.high,
                                            gaplessPlayback: true,
                                          ),
                                          const SizedBox(width: 16),
                                          Text('QRide', style: wordStyle),
                                        ],
                                      ),
                                      const SizedBox(height: 28),
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
                                    backgroundColor: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : const Color(0xFF2D1F35)
                                            .withValues(alpha: 0.08),
                                    valueColor: AlwaysStoppedAnimation(
                                      isDark
                                          ? const Color(0xFFD0C4F0)
                                          : const Color(0xFF6B4E8C),
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
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.38)
                                      : const Color(0xFF2D1F35)
                                          .withValues(alpha: 0.35),
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
