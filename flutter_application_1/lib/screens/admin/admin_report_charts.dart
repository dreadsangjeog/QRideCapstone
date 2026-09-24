import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ReportLineSeries {
  const ReportLineSeries({
    required this.values,
    required this.color,
    required this.label,
  });

  final List<double> values;
  final Color color;
  final String label;
}

class ReportLineChart extends StatelessWidget {
  const ReportLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 220,
  });

  final List<String> labels;
  final List<ReportLineSeries> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _LineChartPainter(
          labels: labels,
          series: series,
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          gridColor: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.45),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.labels,
    required this.series,
    required this.labelColor,
    required this.gridColor,
  });

  final List<String> labels;
  final List<ReportLineSeries> series;
  final Color labelColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || series.isEmpty) return;
    const left = 28.0;
    const bottom = 28.0;
    const top = 12.0;
    const right = 8.0;
    final chart = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (chart.width <= 0 || chart.height <= 0) return;

    var maxY = 1.0;
    for (final s in series) {
      for (final v in s.values) {
        maxY = math.max(maxY, v);
      }
    }
    maxY = _niceMax(maxY);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final text = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final t = i / 4;
      final y = chart.bottom - chart.height * t;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      text.text = TextSpan(
        text: (maxY * t).round().toString(),
        style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w600),
      );
      text.layout();
      text.paint(canvas, Offset(chart.left - text.width - 6, y - text.height / 2));
    }

    for (final s in series) {
      if (s.values.isEmpty) continue;
      final path = _smoothPath(s.values, chart, maxY);
      final fill = Path.from(path)
        ..lineTo(chart.right, chart.bottom)
        ..lineTo(chart.left, chart.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(chart.left, chart.top),
            Offset(chart.left, chart.bottom),
            [
              s.color.withValues(alpha: 0.28),
              s.color.withValues(alpha: 0.02),
            ],
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (s.values.length == 1 || labels.length == 1) {
        canvas.drawCircle(
          Offset(chart.left, chart.bottom - (s.values.first / maxY) * chart.height),
          4,
          Paint()..color = s.color,
        );
      }
    }

    final step = labels.length <= 8
        ? 1
        : (labels.length / 7).ceil();
    for (var i = 0; i < labels.length; i += step) {
      final x = labels.length == 1
          ? chart.left
          : chart.left + (chart.width * i / (labels.length - 1));
      text.text = TextSpan(
        text: labels[i],
        style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w600),
      );
      text.layout(maxWidth: 54);
      text.paint(canvas, Offset(x - text.width / 2, chart.bottom + 8));
    }
  }

  Path _smoothPath(List<double> values, Rect chart, double maxY) {
    final n = values.length;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          n == 1 ? chart.left : chart.left + chart.width * i / (n - 1),
          chart.bottom - (values[i] / maxY) * chart.height,
        ),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (n == 1) return path;
    if (n == 2) {
      path.lineTo(pts.last.dx, pts.last.dy);
      return path;
    }
    for (var i = 0; i < n - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final c1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final c2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p1.dx, p1.dy);
    }
    return path;
  }

  double _niceMax(double v) {
    if (v <= 4) return 4;
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = (v / mag).ceil();
    return (n * mag).toDouble();
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.labels != labels || oldDelegate.series != series;
}

class ReportBarChart extends StatelessWidget {
  const ReportBarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.color,
    this.height = 200,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarChartPainter(
          labels: labels,
          values: values,
          color: color,
          labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          trackColor: color.withValues(alpha: 0.10),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.labels,
    required this.values,
    required this.color,
    required this.labelColor,
    required this.trackColor,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final Color labelColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty) return;
    const bottom = 26.0;
    const top = 16.0;
    final chartH = size.height - top - bottom;
    final maxY = math.max(1.0, values.fold<double>(0, math.max));
    final slot = size.width / labels.length;
    final barW = math.min(28.0, slot * 0.46);
    final text = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < labels.length; i++) {
      final cx = slot * i + slot / 2;
      final h = (values[i] / maxY) * chartH;
      final track = RRect.fromLTRBR(
        cx - barW / 2,
        top,
        cx + barW / 2,
        top + chartH,
        const Radius.circular(10),
      );
      canvas.drawRRect(track, Paint()..color = trackColor);
      final bar = RRect.fromLTRBR(
        cx - barW / 2,
        top + chartH - h,
        cx + barW / 2,
        top + chartH,
        const Radius.circular(10),
      );
      canvas.drawRRect(
        bar,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, top + chartH - h),
            Offset(cx, top + chartH),
            [color, color.withValues(alpha: 0.72)],
          ),
      );
      if (values[i] > 0) {
        text.text = TextSpan(
          text: values[i].round().toString(),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        );
        text.layout();
        text.paint(
          canvas,
          Offset(cx - text.width / 2, top + chartH - h - text.height - 2),
        );
      }
      text.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: labelColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
      text.layout();
      text.paint(canvas, Offset(cx - text.width / 2, size.height - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.labels != labels;
}

class ReportDonutChart extends StatelessWidget {
  const ReportDonutChart({
    super.key,
    required this.slices,
    this.size = 148,
    this.centerLabel,
    this.centerValue,
  });

  final List<({String label, int value, Color color})> slices;
  final double size;
  final String? centerLabel;
  final String? centerValue;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, b) => a + b.value);
    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(slices: slices, total: total),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (centerValue != null)
                    Text(
                      centerValue!,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                          ),
                    ),
                  if (centerLabel != null)
                    Text(
                      centerLabel!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${s.value}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: s.color,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total});

  final List<({String label, int value, Color color})> slices;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: c, radius: r - 8);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.butt;

    if (total <= 0) {
      paint.color = const Color(0x11000000);
      canvas.drawArc(rect, 0, math.pi * 2, false, paint);
      return;
    }

    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * math.pi * 2;
      paint.color = s.color;
      canvas.drawArc(rect, start, sweep - 0.04, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.total != total;
}
