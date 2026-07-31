part of 'user_scan_screen.dart';

/// Normalizes QR text: plain bike code, or `?code=` / last path segment for URLs.
String normalizeBikeCodeFromScan(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return t;
  final uri = Uri.tryParse(t);
  if (uri != null &&
      (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https'))) {
    final q = uri.queryParameters['code'] ?? uri.queryParameters['bike'];
    if (q != null && q.trim().isNotEmpty) return q.trim();
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (seg.isNotEmpty) return seg.last;
  }
  return t;
}

/// Centered square scan area (matches [MobileScanner.scanWindow] layout).
Rect scanWindowRectForLayout(Size size) {
  final shortest = size.width < size.height ? size.width : size.height;
  final frame = shortest * 0.68;
  final left = (size.width - frame) / 2;
  final top = (size.height - frame) / 2 - shortest * 0.05;
  return Rect.fromLTWH(left, top, frame, frame);
}

/// Dimmed mask outside a rounded [frame] + white corner brackets (pass-through for taps).
class ScanFrameOverlayPainter extends CustomPainter {
  ScanFrameOverlayPainter({
    required this.frame,
    this.cornerRadius = 20,
  });

  final Rect frame;
  final double cornerRadius;

  /// Slightly blue-tinted scrim reads cleaner on camera than flat gray-black.
  static const _dim = Color(0xB8171C22);
  static const _arm = 42.0;
  static const _stroke = 3.5;
  static const _cornerColor = Color(0xFFF5F8FC);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      frame,
      Radius.circular(cornerRadius),
    );
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()..addRRect(hole);
    final mask = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(mask, Paint()..color = _dim);

    final corner = Paint()
      ..color = _cornerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final l = frame.left;
    final t = frame.top;
    final r = frame.right;
    final b = frame.bottom;

    canvas.drawLine(Offset(l, t + _arm), Offset(l, t), corner);
    canvas.drawLine(Offset(l, t), Offset(l + _arm, t), corner);
    canvas.drawLine(Offset(r - _arm, t), Offset(r, t), corner);
    canvas.drawLine(Offset(r, t), Offset(r, t + _arm), corner);
    canvas.drawLine(Offset(l, b - _arm), Offset(l, b), corner);
    canvas.drawLine(Offset(l, b), Offset(l + _arm, b), corner);
    canvas.drawLine(Offset(r - _arm, b), Offset(r, b), corner);
    canvas.drawLine(Offset(r, b), Offset(r, b - _arm), corner);
  }

  @override
  bool shouldRepaint(covariant ScanFrameOverlayPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.cornerRadius != cornerRadius;
  }

  @override
  bool? hitTest(Offset position) => false;
}
