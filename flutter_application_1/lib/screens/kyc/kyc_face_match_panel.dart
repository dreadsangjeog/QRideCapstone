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
    _pulse.stop();
    setState(() {
      _step = 3;
      _outcome = result;
    });
    final verdict = result.faceVerdict;
    await Future<void>.delayed(
      Duration(milliseconds: verdict == KycFaceVerdict.match ? 1500 : 2400),
    );
    if (mounted) widget.onFinished(result);
  }

  String _title(KycAutoMatchResult? result) {
    if (result == null) return 'Matching faces';
    return switch ((result.faceVerdict, result.unreadable)) {
      (KycFaceVerdict.match, _) => 'Faces match',
      (KycFaceVerdict.unsure, _) => 'Sent to staff',
      (KycFaceVerdict.mismatch, _) => 'Faces did not match',
      (_, KycFaceStep.idPhoto) => 'ID photo not clear',
      (_, KycFaceStep.liveSelfie) => 'Selfie not clear',
      _ => 'Could not compare',
    };
  }

  /// ID face, live selfie, and same person, once the result is in.
  List<_Mark> _resultMarks(KycAutoMatchResult result) {
    return switch ((result.faceVerdict, result.unreadable)) {
      (KycFaceVerdict.match, _) => const [_Mark.yes, _Mark.yes, _Mark.yes],
      (KycFaceVerdict.unsure, _) => const [_Mark.yes, _Mark.yes, _Mark.maybe],
      (KycFaceVerdict.mismatch, _) => const [_Mark.yes, _Mark.yes, _Mark.no],
      (_, KycFaceStep.idPhoto) => const [_Mark.no, _Mark.skipped, _Mark.skipped],
      (_, KycFaceStep.liveSelfie) => const [_Mark.yes, _Mark.no, _Mark.skipped],
      _ => const [_Mark.skipped, _Mark.skipped, _Mark.no],
    };
  }

  _Mark _mark(int index) {
    final result = _outcome;
    if (result != null) return _resultMarks(result)[index];
    return _step < index ? _Mark.todo : _Mark.busy;
  }

  Color? _ring(KycAutoMatchResult? result) {
    return switch (result?.faceVerdict) {
      KycFaceVerdict.match => _Mark.yes.color,
      KycFaceVerdict.unsure => _Mark.maybe.color,
      KycFaceVerdict.mismatch => _Mark.no.color,
      null => null,
    };
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
    final ring = _ring(result);
    final samePerson = switch (result?.faceVerdict) {
      KycFaceVerdict.match => 'Strong match',
      KycFaceVerdict.unsure => 'Staff will compare',
      KycFaceVerdict.mismatch => 'No match',
      null => null,
    };
    return ColoredBox(
      color: const Color(0xF20B0F14),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _title(result),
                  key: ValueKey(_title(result)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
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
                            label: result?.idFace == null ? 'ID photo' : 'ID face',
                            bytes: result?.idFace ?? widget.idPhoto,
                            scanning: result == null,
                            ring: ring,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _photoCard(
                            label: 'Live selfie',
                            bytes: result?.liveFace ?? widget.selfie,
                            scanning: result == null,
                            ring: ring,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _row('ID face', _mark(0)),
              const SizedBox(height: 8),
              _row('Live selfie', _mark(1)),
              const SizedBox(height: 8),
              _row('Same person', _mark(2), detail: samePerson),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoCard({
    required String label,
    required Uint8List bytes,
    required bool scanning,
    Color? ring,
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ring ?? Colors.transparent,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: ring?.withValues(alpha: 0.28) ??
                      Color.fromRGBO(
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: Image.memory(
                      bytes,
                      key: ValueKey(identityHashCode(bytes)),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
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

  Widget _row(String label, _Mark mark, {String? detail}) {
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
                  ? CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: mark.color,
                    )
                  : Icon(mark.icon, size: 22, color: mark.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: mark == _Mark.skipped ? Colors.white54 : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (detail != null)
              Text(
                detail,
                style: TextStyle(
                  color: mark.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _Mark {
  todo(Icons.radio_button_unchecked, Colors.white38),
  busy(Icons.radio_button_unchecked, Color(0xFF0A84FF)),
  yes(Icons.check_circle_rounded, Color(0xFF34C759)),
  maybe(Icons.help_rounded, Color(0xFFFFB020)),
  no(Icons.cancel_rounded, Color(0xFFFF453A)),
  skipped(Icons.remove_circle_outline_rounded, Colors.white38);

  const _Mark(this.icon, this.color);

  final IconData icon;
  final Color color;
}

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
