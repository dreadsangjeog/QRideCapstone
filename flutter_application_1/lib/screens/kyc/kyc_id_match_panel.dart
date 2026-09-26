import 'dart:typed_data';

import 'package:flutter/material.dart';

class KycIdMatchOutcome {
  const KycIdMatchOutcome({
    required this.ok,
    required this.nameOk,
    required this.firstOk,
    required this.lastOk,
    required this.faceOk,
    required this.hint,
  });

  final bool ok;
  final bool nameOk;
  final bool firstOk;
  final bool lastOk;
  final bool faceOk;
  final String hint;
}

/// Full-screen theater while QRide reads the ID and matches first / last name.
class KycIdMatchPanel extends StatefulWidget {
  const KycIdMatchPanel({
    super.key,
    required this.photo,
    required this.firstName,
    required this.lastName,
    required this.work,
    required this.onFinished,
  });

  final Uint8List photo;
  final String firstName;
  final String lastName;
  final Future<KycIdMatchOutcome> work;
  final ValueChanged<KycIdMatchOutcome> onFinished;

  @override
  State<KycIdMatchPanel> createState() => _KycIdMatchPanelState();
}

class _KycIdMatchPanelState extends State<KycIdMatchPanel>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  int _step = 0;
  KycIdMatchOutcome? _outcome;

  static const _labels = [
    'Reading the ID',
    'Matching first name',
    'Matching last name',
    'Checking the ID photo',
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
      await Future<void>.delayed(const Duration(milliseconds: 620));
    }
    final result = await widget.work;
    if (!mounted) return;
    _scan.stop();
    setState(() {
      _step = 4;
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
              const SizedBox(height: 8),
              Text(
                result == null
                    ? 'Matching your ID'
                    : (result.ok ? 'ID matched' : 'Needs another photo'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result == null
                    ? 'Comparing the printed name and photo to ${widget.firstName} ${widget.lastName}.'
                    : result.hint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_pulse, _scan]),
                    builder: (context, _) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(
                                10,
                                132,
                                255,
                                result == null
                                    ? 0.18 + _pulse.value * 0.22
                                    : 0.08,
                              ),
                              blurRadius: 28,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.memory(
                                widget.photo,
                                fit: BoxFit.contain,
                              ),
                              if (result == null)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _ScanPainter(t: _scan.value),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _stepRow('First name', widget.firstName, _mark(1, result?.firstOk)),
              const SizedBox(height: 8),
              _stepRow('Last name', widget.lastName, _mark(2, result?.lastOk)),
              const SizedBox(height: 8),
              _stepRow('ID photo', 'Printed face', _mark(3, result?.faceOk)),
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

  Widget _stepRow(String label, String value, _Mark mark) {
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
        colors: [
          const Color(0x000A84FF),
          const Color(0x880A84FF),
          const Color(0x000A84FF),
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
