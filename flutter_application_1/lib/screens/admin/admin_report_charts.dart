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

/// Smooth area line chart. Hover (web/desktop) or tap/drag (touch) shows a
/// guide line and a details card for the nearest point.
class ReportLineChart extends StatefulWidget {
  const ReportLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 220,
    this.tooltipTitle,
    this.tooltipLines,
    this.showAxes = true,
    this.onDark = false,
    this.yLabel,
  });

  final List<String> labels;
  final List<ReportLineSeries> series;
  final double height;

  /// Heading of the hover card for point [index]; defaults to [labels].
  final String Function(int index)? tooltipTitle;

  /// Body lines of the hover card; defaults to one line per series value.
  final List<({String label, String value, Color color})> Function(int index)?
      tooltipLines;

  final bool showAxes;
  final bool onDark;
  final String Function(double value)? yLabel;

  @override
  State<ReportLineChart> createState() => _ReportLineChartState();
}

class _ReportLineChartState extends State<ReportLineChart> {
  int? _hover;

  int get _count => widget.series.isEmpty
      ? 0
      : widget.series.map((s) => s.values.length).reduce(math.max);

  void _updateHover(Offset local, Size size) {
    final n = _count;
    if (n == 0) return;
    final rect = _LineChartPainter.chartRect(size, widget.showAxes);
    final int index;
    if (n == 1) {
      index = 0;
    } else {
      final t = ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0);
      index = (t * (n - 1)).round();
    }
    if (index != _hover) setState(() => _hover = index);
  }

  void _clear() {
    if (_hover != null) setState(() => _hover = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelColor = widget.onDark
        ? Colors.white.withValues(alpha: 0.72)
        : cs.onSurfaceVariant;
    final gridColor = widget.onDark
        ? Colors.white.withValues(alpha: 0.14)
        : cs.outlineVariant.withValues(alpha: 0.45);

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, widget.height);
          final painter = _LineChartPainter(
            labels: widget.labels,
            series: widget.series,
            labelColor: labelColor,
            gridColor: gridColor,
            showAxes: widget.showAxes,
            hover: _hover,
            guideColor: widget.onDark
                ? Colors.white.withValues(alpha: 0.55)
                : cs.onSurfaceVariant.withValues(alpha: 0.45),
            dotFill: widget.onDark ? const Color(0xFF0A5FCF) : cs.surface,
            yLabel: widget.yLabel,
          );
          final hover = _hover;
          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (e) => _updateHover(e.localPosition, size),
            onExit: (_) => _clear(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _updateHover(d.localPosition, size),
              onHorizontalDragUpdate: (d) =>
                  _updateHover(d.localPosition, size),
              onHorizontalDragEnd: (_) => _clear(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: CustomPaint(painter: painter)),
                  if (hover != null && hover < _count)
                    _tooltip(context, size, hover, painter),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tooltip(
    BuildContext context,
    Size size,
    int index,
    _LineChartPainter painter,
  ) {
    const cardWidth = 176.0;
    final point = painter.pointFor(size, index, 0);
    final title = widget.tooltipTitle?.call(index) ??
        (index < widget.labels.length ? widget.labels[index] : '');
    final lines = widget.tooltipLines?.call(index) ??
        [
          for (final s in widget.series)
            if (index < s.values.length)
              (
                label: s.label,
                value: s.values[index].round().toString(),
                color: s.color,
              ),
        ];

    var left = point.dx + 14;
    if (left + cardWidth > size.width) left = point.dx - 14 - cardWidth;
    left = left.clamp(0.0, math.max(0.0, size.width - cardWidth));

    return Positioned(
      left: left,
      top: 0,
      width: cardWidth,
      child: IgnorePointer(
        child: Material(
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 6),
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: l.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            l.label,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          l.value,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
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
    required this.showAxes,
    required this.hover,
    required this.guideColor,
    required this.dotFill,
    this.yLabel,
  });

  final List<String> labels;
  final List<ReportLineSeries> series;
  final Color labelColor;
  final Color gridColor;
  final bool showAxes;
  final int? hover;
  final Color guideColor;
  final Color dotFill;
  final String Function(double value)? yLabel;

  static Rect chartRect(Size size, bool showAxes) {
    final left = showAxes ? 34.0 : 6.0;
    final bottom = showAxes ? 28.0 : 6.0;
    const top = 12.0;
    const right = 8.0;
    return Rect.fromLTWH(
      left,
      top,
      math.max(0, size.width - left - right),
      math.max(0, size.height - top - bottom),
    );
  }

  double get _maxY {
    var maxY = 1.0;
    for (final s in series) {
      for (final v in s.values) {
        maxY = math.max(maxY, v);
      }
    }
    return _niceMax(maxY);
  }

  Offset pointFor(Size size, int index, int seriesIndex) {
    final chart = chartRect(size, showAxes);
    final s = series[seriesIndex];
    final n = s.values.length;
    final x = n <= 1 ? chart.left : chart.left + chart.width * index / (n - 1);
    final v = index < n ? s.values[index] : 0.0;
    return Offset(x, chart.bottom - (v / _maxY) * chart.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || series.isEmpty) return;
    final chart = chartRect(size, showAxes);
    if (chart.width <= 0 || chart.height <= 0) return;
    final maxY = _maxY;
    final text = TextPainter(textDirection: TextDirection.ltr);

    if (showAxes) {
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      for (var i = 0; i <= 4; i++) {
        final t = i / 4;
        final y = chart.bottom - chart.height * t;
        canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
        final v = maxY * t;
        text.text = TextSpan(
          text: yLabel?.call(v) ?? v.round().toString(),
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        );
        text.layout();
        text.paint(
          canvas,
          Offset(chart.left - text.width - 6, y - text.height / 2),
        );
      }
    }

    for (final s in series) {
      if (s.values.isEmpty) continue;
      final path = _smoothPath(s.values, chart, maxY);
      final fill = Path.from(path)
        ..lineTo(
          s.values.length == 1 ? chart.left : chart.right,
          chart.bottom,
        )
        ..lineTo(chart.left, chart.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(chart.left, chart.top),
            Offset(chart.left, chart.bottom),
            [
              s.color.withValues(alpha: 0.30),
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
    }

    final h = hover;
    if (h != null) {
      final x = pointFor(size, h, 0).dx;
      final guide = Paint()
        ..color = guideColor
        ..strokeWidth = 1.2;
      const dash = 4.0;
      for (var y = chart.top; y < chart.bottom; y += dash * 2) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, math.min(y + dash, chart.bottom)),
          guide,
        );
      }
      for (var i = 0; i < series.length; i++) {
        if (h >= series[i].values.length) continue;
        final p = pointFor(size, h, i);
        canvas.drawCircle(
          p,
          7,
          Paint()..color = series[i].color.withValues(alpha: 0.22),
        );
        canvas.drawCircle(p, 4.5, Paint()..color = dotFill);
        canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = series[i].color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4,
        );
      }
    }

    if (!showAxes) return;
    final step = labels.length <= 8 ? 1 : (labels.length / 7).ceil();
    for (var i = 0; i < labels.length; i += step) {
      final x = labels.length == 1
          ? chart.left
          : chart.left + (chart.width * i / (labels.length - 1));
      text.text = TextSpan(
        text: labels[i],
        style: TextStyle(
          color: h == i ? guideColor.withValues(alpha: 1) : labelColor,
          fontSize: 10,
          fontWeight: h == i ? FontWeight.w800 : FontWeight.w600,
        ),
      );
      text.layout(maxWidth: 60);
      final dx = (x - text.width / 2).clamp(0.0, size.width - text.width);
      text.paint(canvas, Offset(dx, chart.bottom + 8));
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
    for (var i = 0; i < n - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final mx = p0.dx + (p1.dx - p0.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }
    return path;
  }

  static double _niceMax(double v) {
    if (v <= 4) return 4;
    final mag = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final n = (v / mag).ceil();
    return n * mag;
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.hover != hover ||
      old.labels != labels ||
      old.series != series ||
      old.labelColor != labelColor;
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

    final nonZero = slices.where((s) => s.value > 0).length;
    final gap = nonZero > 1 ? 0.04 : 0.0;
    var start = -math.pi / 2;
    for (final s in slices) {
      if (s.value <= 0) continue;
      final sweep = (s.value / total) * math.pi * 2;
      paint.color = s.color;
      canvas.drawArc(rect, start, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.total != total;
}
