import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../theme/login_season.dart';

const _winterBg = 'assets/images/login_winter_bg.jpg';
const _winterFg = 'assets/images/login_winter_fg.png';
const _winterRider = 'assets/images/login_rider.png';
const _summerBg = 'assets/images/login_summer_bg.jpg';
const _summerFg = 'assets/images/login_summer_fg.png';
const _summerRider = 'assets/images/login_rider_summer.png';

// Scene art is 1280×720; background and foreground share the same framing.
const _sceneW = 1280.0;
const _sceneH = 720.0;
// Where tyres meet the road, as a fraction of scene height.
const _roadContact = 0.815;
// Rider height in scene pixels.
const _riderSceneH = 160.0;
// Cruising speed in scene pixels per second.
const _cruise = 120.0;
// Below this width the rider would crowd the form, so only snow animates.
const _riderMinWidth = 700.0;

// Winter rider art is 636×673. Summer rider art is square.
const _winterRiderW = 636.0;
const _winterRiderH = 673.0;
const _summerRiderW = 512.0;
const _summerRiderH = 512.0;
const _summerTyreR = 90.0;
const _summerRim = 82.0;
const _summerHubs = [Offset(106, 408), Offset(405, 408)];
const _wheelHubs = [Offset(123, 548), Offset(511, 548)];
const _tyreR = 123.0;
const _rimR = 102.0;

/// Winter park behind login: rider on the road between the background and
/// the foreground trees, with snow falling over everything.
class LoginSceneBackdrop extends StatefulWidget {
  const LoginSceneBackdrop({
    super.key,
    required this.child,
    this.showRider = true,
  });

  final Widget child;
  final bool showRider;

  @override
  State<LoginSceneBackdrop> createState() => _LoginSceneBackdropState();
}

class _LoginSceneBackdropState extends State<LoginSceneBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _elapsed = ValueNotifier<double>(0);
  late final List<_Flake> _flakes;

  @override
  void initState() {
    super.initState();
    final rng = math.Random(21);
    _flakes = List.generate(70, (i) => _Flake.seed(rng));
    _ticker = createTicker((d) => _elapsed.value = d.inMicroseconds / 1e6)
      ..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final a in const [
      _winterBg,
      _winterFg,
      _winterRider,
      _summerBg,
      _summerFg,
      _summerRider,
    ]) {
      precacheImage(AssetImage(a), context);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  Widget _layer(String asset) => Image.asset(
    asset,
    fit: BoxFit.cover,
    alignment: Alignment.bottomCenter,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LoginSeason>(
      valueListenable: loginSeason,
      builder: (context, season, _) {
        final summer = season == LoginSeason.summer;
        final bg = summer ? _summerBg : _winterBg;
        final fg = summer ? _summerFg : _winterFg;
        final riderAsset = summer ? _summerRider : _winterRider;
        final artW = summer ? _summerRiderW : _winterRiderW;
        final artH = summer ? _summerRiderH : _winterRiderH;
        return LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            final s = math.max(w / _sceneW, h / _sceneH);
            final sceneTop = h - _sceneH * s;

            final riderH = _riderSceneH * s;
            final riderW = riderH * artW / artH;
            final bottom = h - (sceneTop + _roadContact * _sceneH * s);
            final span = w + riderW;
            final speed = _cruise * s;
            final artTyre = summer ? _summerTyreR : _tyreR;
            final tyreR = artTyre * riderH / artH;
            final showRider = widget.showRider && w >= _riderMinWidth;
            final flakeCount = summer
                ? 16
                : (w * h / 22000).round().clamp(28, _flakes.length);
            final flakes = _flakes.take(flakeCount).toList();
            Widget scene(String asset) => showRider
                ? _layer(asset)
                : Transform.scale(
                    scale: 1.18,
                    alignment: Alignment.topCenter,
                    child: _layer(asset),
                  );

            final rider = Image.asset(
              riderAsset,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: summer
                      ? const Color(0xFFD7F0C8)
                      : const Color(0xFFDCEBFA),
                ),
                scene(bg),
                if (showRider)
                  ValueListenableBuilder<double>(
                    valueListenable: _elapsed,
                    builder: (context, t, _) {
                      // One rider: left to right, then she turns and comes back.
                      final dist = (t * speed) % (span * 2);
                      final goingRight = dist <= span;
                      final along = goingRight ? dist : (span * 2 - dist);
                      final left = along - riderW;
                      final sprite = CustomPaint(
                        painter: _WheelPainter(
                          angle: t * speed / tyreR,
                          summer: summer,
                          shadow: true,
                          spokes: true,
                        ),
                        child: rider,
                      );
                      return Positioned(
                        left: left,
                        bottom: bottom,
                        width: riderW,
                        height: riderH,
                        child: goingRight
                            ? sprite
                            : Transform.flip(flipX: true, child: sprite),
                      );
                    },
                  ),
                IgnorePointer(child: scene(fg)),
                IgnorePointer(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _elapsed,
                    builder: (context, t, _) => CustomPaint(
                      painter: _SnowPainter(
                        t: t,
                        flakes: flakes,
                        summer: summer,
                      ),
                    ),
                  ),
                ),
                widget.child,
              ],
            );
          },
        );
      },
    );
  }

}

/// Road shadow and spokes behind the rider art. Spokes turn at speed / radius,
/// so the wheels roll without slipping.
class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.angle,
    required this.summer,
    required this.shadow,
    required this.spokes,
  });

  final double angle;
  final bool summer;
  final bool shadow;
  final bool spokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(
      size.width / (summer ? _summerRiderW : _winterRiderW),
      size.height / (summer ? _summerRiderH : _winterRiderH),
    );

    final artW = summer ? _summerRiderW : _winterRiderW;
    final artH = summer ? _summerRiderH : _winterRiderH;
    if (shadow) {
      canvas.drawOval(
        Rect.fromLTRB(30, artH - 18, artW - 30, artH + 12),
        Paint()
          ..color = (summer ? const Color(0xFF2E6B32) : const Color(0xFF3B5B85))
              .withValues(alpha: 0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    if (!spokes) {
      canvas.restore();
      return;
    }

    final spoke = Paint()
      ..color = const Color(0xFF8E9BB0)
      ..strokeWidth = summer ? 2.2 : 2.6
      ..strokeCap = StrokeCap.round;
    const count = 18;
    final hubs = summer ? _summerHubs : _wheelHubs;
    final rim = summer ? _summerRim : _rimR;
    final inner = summer ? 8.0 : 12.0;
    for (final hub in hubs) {
      for (var i = 0; i < count; i++) {
        final a = angle + i * math.pi * 2 / count;
        canvas.drawLine(
          hub + Offset(math.cos(a), math.sin(a)) * inner,
          hub + Offset(math.cos(a), math.sin(a)) * rim,
          spoke,
        );
      }
      canvas.drawCircle(
        hub,
        summer ? 7 : 12,
        Paint()..color = summer ? const Color(0xFF1E4F86) : QrideBrand.accentDeep,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.summer != summer ||
      oldDelegate.spokes != spokes ||
      oldDelegate.shadow != shadow;
}

class _Flake {
  const _Flake({
    required this.x,
    required this.phase,
    required this.fall,
    required this.size,
    required this.sway,
  });

  factory _Flake.seed(math.Random rng) {
    final size = 1.4 + rng.nextDouble() * 3.2;
    return _Flake(
      x: rng.nextDouble(),
      phase: rng.nextDouble(),
      // Bigger flakes are nearer, so they fall faster.
      fall: 22 + size * 12 + rng.nextDouble() * 10,
      size: size,
      sway: 6 + rng.nextDouble() * 14,
    );
  }

  final double x;
  final double phase;
  final double fall;
  final double size;
  final double sway;
}

class _SnowPainter extends CustomPainter {
  const _SnowPainter({
    required this.t,
    required this.flakes,
    required this.summer,
  });

  final double t;
  final List<_Flake> flakes;
  final bool summer;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final span = size.height + 24;
    if (!summer) {
      for (final f in flakes) {
        final y = (f.phase * span + t * f.fall) % span - 12;
        final x = f.x * size.width +
            math.sin(t * 0.9 + f.phase * math.pi * 2) * f.sway;
        paint.color = Colors.white.withValues(alpha: 0.55 + f.size / 12);
        canvas.drawCircle(Offset(x, y), f.size, paint);
      }
      return;
    }
    // Drifting leaves, not snow.
    const colors = [
      Color(0xFF7CB342),
      Color(0xFF9CCC65),
      Color(0xFFFFB300),
      Color(0xFFEF6C00),
    ];
    for (var i = 0; i < flakes.length; i++) {
      final f = flakes[i];
      final y = (f.phase * span + t * f.fall * 0.28) % span - 12;
      final x = f.x * size.width +
          math.sin(t * 0.5 + f.phase * math.pi * 2) * f.sway;
      paint.color = colors[i % colors.length].withValues(alpha: 0.8);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: f.size * 2.4,
          height: f.size * 1.2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.summer != summer;
}

/// Transparent app bar for auth screens drawn over [LoginSceneBackdrop].
PreferredSizeWidget authSceneAppBar() => AppBar(
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
);

/// Frosted strip for admin / rider app bars, ending in a lit glass edge.
class GlassAppBarBackdrop extends StatelessWidget {
  const GlassAppBarBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [Color(0xF2101828), Color(0xF0101828)]
                  : [
                      Colors.white.withValues(alpha: 0.62),
                      Colors.white.withValues(alpha: 0.44),
                    ],
            ),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bright rim on top, darker hairline below: reads as a glass
                // edge on both light and dark washes.
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.95),
                ),
                Container(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFF5B86AD).withValues(alpha: 0.38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft shadow cast by the glass header onto the page. Put it at the top of
/// the body — the app bar clips anything drawn below its own bounds.
class GlassHeaderShadow extends StatelessWidget {
  const GlassHeaderShadow({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? Colors.black : const Color(0xFF3D6A94);
    return IgnorePointer(
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.withValues(alpha: isDark ? 0.40 : 0.13),
              c.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Places [GlassHeaderShadow] over the top of [child].
Widget withGlassHeaderShadow(Widget child) => Stack(
  fit: StackFit.expand,
  children: [
    child,
    const Positioned(top: 0, left: 0, right: 0, child: GlassHeaderShadow()),
  ],
);

/// Winter login art is designed for light. Keeps auth screens readable when
/// the phone is in system dark mode.
class AuthLightTheme extends StatelessWidget {
  const AuthLightTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = qrideTheme(qrideLightScheme()).copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.84),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
    return Theme(
      data: light,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: const Color(0xFFDCEBFA),
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: child,
      ),
    );
  }
}

/// Pins auth content toward the top so the form is not sitting on the road.
class AuthSceneBody extends StatelessWidget {
  const AuthSceneBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 24),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600) {
            return Center(
              child: SingleChildScrollView(
                padding: padding.copyWith(top: 24),
                child: child,
              ),
            );
          }
          final top = (constraints.maxHeight * 0.05).clamp(12.0, 28.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: padding.copyWith(top: top),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Frosted white card used on top of [LoginSceneBackdrop].
class GlassLoginCard extends StatelessWidget {
  const GlassLoginCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: QrideBrand.accentDeep.withValues(alpha: 0.14),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
