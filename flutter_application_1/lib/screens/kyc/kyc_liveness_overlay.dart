import 'package:flutter/material.dart';

/// Ring states, in order of progress through a pose.
enum KycGuideState { searching, aligned, holding, action, captured }

/// Full-screen oval the rider must fill. Give it a real size (`Positioned.fill`).
class KycFaceGuide extends StatefulWidget {
  const KycFaceGuide({
    super.key,
    required this.state,
    required this.holdProgress,
    this.caption,
  });

  final KycGuideState state;

  /// 0..1 progress of the "hold still" timer.
  final double holdProgress;

  /// Small text drawn inside the oval.
  final String? caption;

  static Rect ovalOn(Size size) {
    final width = size.width * 0.66;
    final height = size.height * 0.50;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: width,
      height: height,
    );
  }

  @override
  State<KycFaceGuide> createState() => _KycFaceGuideState();
}

class _KycFaceGuideState extends State<KycFaceGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color get _target => switch (widget.state) {
        KycGuideState.searching => Colors.white,
        KycGuideState.aligned => const Color(0xFF0A84FF),
        KycGuideState.holding => const Color(0xFF0A84FF),
        KycGuideState.action => const Color(0xFFFFD60A),
        KycGuideState.captured => const Color(0xFF34C759),
      };

  @override
  Widget build(BuildContext context) {
    final animate = widget.state == KycGuideState.aligned ||
        widget.state == KycGuideState.action;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _target),
      duration: const Duration(milliseconds: 320),
      builder: (context, ring, _) {
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            return CustomPaint(
              painter: _KycFaceOvalPainter(
                ring: ring ?? Colors.white,
                holdProgress: widget.holdProgress.clamp(0, 1),
                pulse: animate ? _pulse.value : 0,
              ),
              child: SizedBox.expand(
                child: widget.caption == null
                    ? null
                    : Align(
                        alignment: const Alignment(0, -0.10),
                        child: Text(
                          widget.caption!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            shadows: [
                              Shadow(blurRadius: 10, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _KycFaceOvalPainter extends CustomPainter {
  _KycFaceOvalPainter({
    required this.ring,
    required this.holdProgress,
    required this.pulse,
  });

  final Color ring;
  final double holdProgress;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 8 || size.height < 8) return;
    final hole = KycFaceGuide.ovalOn(size);

    final mask = Path()
      ..addRect(Offset.zero & size)
      ..addOval(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      mask,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );

    if (pulse > 0) {
      canvas.drawOval(
        hole.inflate(6 + pulse * 14),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ring.withValues(alpha: 0.45 * (1 - pulse)),
      );
    }

    canvas.drawOval(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = ring,
    );

    if (holdProgress > 0) {
      canvas.drawArc(
        hole.inflate(20),
        -1.5707963,
        holdProgress * 6.2831853,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = ring,
      );
    }
  }

  @override
  bool shouldRepaint(_KycFaceOvalPainter old) {
    return old.ring != ring ||
        old.holdProgress != holdProgress ||
        old.pulse != pulse;
  }
}
