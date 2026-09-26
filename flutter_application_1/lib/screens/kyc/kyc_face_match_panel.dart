import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/kyc_auto_match_result.dart';

/// Full-screen theater while QRide compares the ID photo to the live selfie.
class KycFaceMatchPanel extends StatefulWidget {
  const KycFaceMatchPanel({
    super.key,
    required this.idPhoto,
    required this.selfie,
    required this.work,
    required this.onFinished,
  });

  final Uint8List idPhoto;
  final Uint8List selfie;
  final Future<KycAutoMatchResult> work;
  final ValueChanged<KycAutoMatchResult> onFinished;

  @override
  State<KycFaceMatchPanel> createState() => _KycFaceMatchPanelState();
}

class _KycFaceMatchPanelState extends State<KycFaceMatchPanel>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  int _step = 0;
  KycAutoMatchResult? _outcome;

  static const _labels = [
    'Finding the ID photo',
    'Reading your live selfie',
    'Comparing the two faces',
  ];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (var i = 0; i < _labels.length; i++) {
      if (!mounted) return;
      setState(() => _step = i);
      await Future<void>.delayed(const Duration(milliseconds: 640));
    }
    final result = await widget.work;
    if (!mounted) return;
    _scan.stop();
    setState(() {
      _step = 3;
      _outcome = result;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (mounted) widget.onFinished(result);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _outcome;
    return ColoredBox(
      color: const Color(0xF20B0F14),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            children: [
              Text(
                result == null
                    ? 'Matching faces'
                    : (result.photoMatch
                        ? 'Ready for staff'
                        : 'Faces did not match'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result == null
                    ? (_labels[_step.clamp(0, _labels.length - 1)])
                    : result.note,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _scan]),
                  builder: (context, _) {
                    return Row(
                      children: [
                        Expanded(
                          child: _photoCard(
                            label: 'ID photo',
                            bytes: widget.idPhoto,
                            scanning: result == null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _photoCard(
                            label: 'Live selfie',
                            bytes: widget.selfie,
                            scanning: result == null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _row('ID face', _mark(0, result?.photoMatch)),
              const SizedBox(height: 8),
              _row('Live selfie', _mark(1, result?.photoMatch)),
              const SizedBox(height: 8),
              _row('Same person', _mark(2, result?.photoMatch)),
            ],
          ),
        ),
      ),
    );
  }

  _Mark _mark(int index, bool? ok) {
    if (_step < index) return _Mark.todo;
    if (ok == null) return _Mark.busy;
    return ok ? _Mark.yes : _Mark.no;
  }

  Widget _photoCard({
    required String label,
    required Uint8List bytes,
    required bool scanning,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(
                    10,
                    132,
                    255,
                    scanning ? 0.16 + _pulse.value * 0.20 : 0.06,
                  ),
                  blurRadius: 22,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  if (scanning)
                    CustomPaint(painter: _ScanPainter(t: _scan.value)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, _Mark mark) {
    final color = switch (mark) {
      _Mark.yes => const Color(0xFF34C759),
      _Mark.no => const Color(0xFFFF453A),
      _Mark.busy => const Color(0xFF0A84FF),
      _Mark.todo => Colors.white38,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: mark == _Mark.busy
                  ? const CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFF0A84FF),
                    )
                  : Icon(
                      mark == _Mark.yes
                          ? Icons.check_circle_rounded
                          : mark == _Mark.no
                              ? Icons.cancel_rounded
                              : Icons.radio_button_unchecked,
                      size: 22,
                      color: color,
                    ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Mark { todo, busy, yes, no }

class _ScanPainter extends CustomPainter {
  const _ScanPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    final y = size.height * t;
    final band = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0x000A84FF),
          Color(0x880A84FF),
          Color(0x000A84FF),
        ],
      ).createShader(Rect.fromLTWH(0, y - 28, size.width, 56));
    canvas.drawRect(Rect.fromLTWH(0, y - 28, size.width, 56), band);
    canvas.drawRect(
      Rect.fromLTWH(0, y - 1.2, size.width, 2.4),
      Paint()..color = const Color(0xFF0A84FF),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter oldDelegate) => oldDelegate.t != t;
}
