import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';

const _bgAsset = 'assets/images/login_winter_bg.jpg';
const _fgAsset = 'assets/images/login_winter_fg.png';
const _riderAsset = 'assets/images/login_rider.png';

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

// Rider art is 636×673 with wheel hubs at these pixels.
const _riderW = 636.0;
const _riderH = 673.0;
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
    for (final a in const [_bgAsset, _fgAsset, _riderAsset]) {
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
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final s = math.max(w / _sceneW, h / _sceneH);
        final sceneTop = h - _sceneH * s;

        final riderH = _riderSceneH * s;
        final riderW = riderH * _riderW / _riderH;
        final bottom = h - (sceneTop + _roadContact * _sceneH * s);
        final lap = w + riderW * 2;
        final speed = _cruise * s;
        final tyreR = _tyreR * riderH / _riderH;
        final showRider = widget.showRider && w >= _riderMinWidth;
        final flakes = _flakes
            .take((w * h / 22000).round().clamp(28, _flakes.length).toInt())
            .toList();
        // With no rider, zoom from the top so the road sits under the footer
        // instead of behind it.
        Widget scene(String asset) => showRider
            ? _layer(asset)
            : Transform.scale(
                scale: 1.18,
                alignment: Alignment.topCenter,
                child: _layer(asset),
              );

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFDCEBFA)),
            scene(_bgAsset),
            if (showRider)
              ValueListenableBuilder<double>(
                valueListenable: _elapsed,
                builder: (context, t, rider) {
                  final travelled = t * speed;
                  return Positioned(
                    left: travelled % lap - riderW,
                    bottom: bottom,
                    width: riderW,
                    height: riderH,
                    child: CustomPaint(
                      painter: _WheelPainter(angle: travelled / tyreR),
                      child: rider,
                    ),
                  );
                },
                child: Image.asset(
                  _riderAsset,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            IgnorePointer(child: scene(_fgAsset)),
            IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _elapsed,
                builder: (context, t, _) => CustomPaint(
                  painter: _SnowPainter(t: t, flakes: flakes),
                ),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}

/// Road shadow and spokes behind the rider art. Spokes turn at speed / radius,
/// so the wheels roll without slipping.
class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.angle});

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _riderW, size.height / _riderH);

    canvas.drawOval(
      Rect.fromLTRB(20, _riderH - 14, _riderW - 20, _riderH + 10),
      Paint()
        ..color = const Color(0xFF3B5B85).withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final spoke = Paint()
      ..color = const Color(0xFF8E9BB0)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    const count = 18;
    for (final hub in _wheelHubs) {
      for (var i = 0; i < count; i++) {
        final a = angle + i * math.pi * 2 / count;
        canvas.drawLine(
          hub + Offset(math.cos(a), math.sin(a)) * 12,
          hub + Offset(math.cos(a), math.sin(a)) * _rimR,
          spoke,
        );
      }
      canvas.drawCircle(hub, 12, Paint()..color = QrideBrand.accentDeep);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.angle != angle;
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
  const _SnowPainter({required this.t, required this.flakes});

  final double t;
  final List<_Flake> flakes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final span = size.height + 24;
    for (final f in flakes) {
      final y = (f.phase * span + t * f.fall) % span - 12;
      final x =
          f.x * size.width + math.sin(t * 0.9 + f.phase * math.pi * 2) * f.sway;
      paint.color = Colors.white.withValues(alpha: 0.55 + f.size / 12);
      canvas.drawCircle(Offset(x, y), f.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnowPainter oldDelegate) => oldDelegate.t != t;
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
                  ? const [Color(0x80101828), Color(0x66101828)]
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
