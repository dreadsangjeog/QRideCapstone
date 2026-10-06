import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'qride_glass.dart';

enum _BirthdatePage { day, month, year }

/// Birthdate calendar with month and year grids for quick jumps. With
/// [startWithYear] it opens on the years and walks year → month → day.
Future<DateTime?> showBirthdatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  bool startWithYear = false,
}) {
  final first = DateUtils.dateOnly(firstDate);
  final last = DateUtils.dateOnly(lastDate);
  var initial = DateUtils.dateOnly(initialDate);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    builder: (context) => _BirthdateDialog(
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      startWithYear: startWithYear,
    ),
  );
}

class _BirthdateDialog extends StatefulWidget {
  const _BirthdateDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.startWithYear,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool startWithYear;

  @override
  State<_BirthdateDialog> createState() => _BirthdateDialogState();
}

class _BirthdateDialogState extends State<_BirthdateDialog> {
  late DateTime _selected = widget.initialDate;
  late DateTime _displayed = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );
  late _BirthdatePage _page = widget.startWithYear
      ? _BirthdatePage.year
      : _BirthdatePage.day;

  bool _monthInRange(DateTime month) {
    final end = DateTime(month.year, month.month + 1, 0);
    return !end.isBefore(widget.firstDate) && !month.isAfter(widget.lastDate);
  }

  void _browse(DateTime month) {
    if (_monthInRange(month)) setState(() => _displayed = month);
  }

  /// Moves the selection to [year]/[month], keeping the day where it fits.
  /// Dates outside the range are clamped so a tap is never ignored.
  void _moveTo(int year, int month, _BirthdatePage page) {
    final days = DateUtils.getDaysInMonth(year, month);
    var next = DateTime(year, month, math.min(_selected.day, days));
    if (next.isBefore(widget.firstDate)) next = widget.firstDate;
    if (next.isAfter(widget.lastDate)) next = widget.lastDate;
    setState(() {
      _selected = next;
      _displayed = DateTime(next.year, next.month);
      _page = page;
    });
  }

  void _toggle(_BirthdatePage page) {
    setState(() => _page = _page == page ? _BirthdatePage.day : page);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bodyHeight = (MediaQuery.sizeOf(context).height * 0.4).clamp(
      270.0,
      320.0,
    );
    final age = _ageOn(_selected, DateUtils.dateOnly(DateTime.now()));
    final prev = DateTime(_displayed.year, _displayed.month - 1);
    final next = DateTime(_displayed.year, _displayed.month + 1);

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlassPanel(
          radius: 26,
          tint: isDark ? null : Colors.white.withValues(alpha: 0.94),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Birthdate',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.yMMMMd().format(_selected),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        if (age > 0)
                          Text(
                            age == 1 ? '1 year old' : '$age years old',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _JumpChip(
                                  label: DateFormat.MMMM().format(_displayed),
                                  hint: 'Choose month',
                                  open: _page == _BirthdatePage.month,
                                  onTap: () => _toggle(_BirthdatePage.month),
                                ),
                                const SizedBox(width: 8),
                                _JumpChip(
                                  label: '${_displayed.year}',
                                  hint: 'Choose year',
                                  open: _page == _BirthdatePage.year,
                                  onTap: () => _toggle(_BirthdatePage.year),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_page == _BirthdatePage.day) ...[
                        IconButton(
                          tooltip: 'Previous month',
                          onPressed: _monthInRange(prev)
                              ? () => _browse(prev)
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        IconButton(
                          tooltip: 'Next month',
                          onPressed: _monthInRange(next)
                              ? () => _browse(next)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: bodyHeight,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(
                          _page == _BirthdatePage.day
                              ? 'day-${_displayed.year}-${_displayed.month}'
                              : _page.name,
                        ),
                        child: switch (_page) {
                          _BirthdatePage.day => _DayGrid(
                            displayed: _displayed,
                            selected: _selected,
                            firstDate: widget.firstDate,
                            lastDate: widget.lastDate,
                            onDay: (day) => setState(() => _selected = day),
                          ),
                          _BirthdatePage.month => _MonthGrid(
                            year: _displayed.year,
                            selectedMonth: _displayed.month,
                            firstDate: widget.firstDate,
                            lastDate: widget.lastDate,
                            onMonth: (month) => _moveTo(
                              _displayed.year,
                              month,
                              _BirthdatePage.day,
                            ),
                          ),
                          _BirthdatePage.year => _YearGrid(
                            firstYear: widget.firstDate.year,
                            lastYear: widget.lastDate.year,
                            selectedYear: _displayed.year,
                            viewportHeight: bodyHeight,
                            onYear: (year) => _moveTo(
                              year,
                              _displayed.month,
                              _BirthdatePage.month,
                            ),
                          ),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(96, 44),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => Navigator.pop(context, _selected),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int _ageOn(DateTime birth, DateTime today) {
  final hadBirthday =
      today.month > birth.month ||
      (today.month == birth.month && today.day >= birth.day);
  return today.year - birth.year - (hadBirthday ? 0 : 1);
}

/// Month or year button in the header. Tinted while its grid is open.
class _JumpChip extends StatelessWidget {
  const _JumpChip({
    required this.label,
    required this.hint,
    required this.open,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fg = open ? cs.primary : cs.onSurface;
    return Semantics(
      button: true,
      label: hint,
      child: Material(
        color: open
            ? cs.primary.withValues(alpha: isDark ? 0.22 : 0.12)
            : cs.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: fg,
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

/// Rounded choice used by the month and year grids.
class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fg = !enabled
        ? cs.onSurface.withValues(alpha: 0.3)
        : selected
        ? cs.onPrimary
        : cs.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? cs.primary
            : cs.onSurface.withValues(alpha: isDark ? 0.07 : 0.045),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.year,
    required this.selectedMonth,
    required this.firstDate,
    required this.lastDate,
    required this.onMonth,
  });

  final int year;
  final int selectedMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<int> onMonth;

  bool _enabled(int month) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1, 0);
    return !end.isBefore(firstDate) && !start.isAfter(lastDate);
  }

  @override
  Widget build(BuildContext context) {
    const gap = 10.0;
    return LayoutBuilder(
      builder: (context, box) {
        final rowHeight = math.min(56.0, (box.maxHeight - gap * 3 - 4) / 4);
        return GridView.builder(
          padding: const EdgeInsets.only(top: 4),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: rowHeight,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
          ),
          itemCount: 12,
          itemBuilder: (context, i) {
            final month = i + 1;
            return _ChoicePill(
              label: DateFormat.MMMM().format(DateTime(year, month)),
              selected: month == selectedMonth,
              enabled: _enabled(month),
              onTap: () => onMonth(month),
            );
          },
        );
      },
    );
  }
}

/// Oldest year at the top. Opens scrolled so the selected year is centred.
class _YearGrid extends StatefulWidget {
  const _YearGrid({
    required this.firstYear,
    required this.lastYear,
    required this.selectedYear,
    required this.viewportHeight,
    required this.onYear,
  });

  final int firstYear;
  final int lastYear;
  final int selectedYear;
  final double viewportHeight;
  final ValueChanged<int> onYear;

  @override
  State<_YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<_YearGrid> {
  static const _columns = 4;
  static const _rowHeight = 48.0;
  static const _gap = 8.0;
  static const _pad = 14.0;

  late final ScrollController _scroll;

  int get _count => widget.lastYear - widget.firstYear + 1;

  @override
  void initState() {
    super.initState();
    final rows = (_count + _columns - 1) ~/ _columns;
    final row = (widget.selectedYear - widget.firstYear) ~/ _columns;
    final content = _pad * 2 + rows * _rowHeight + (rows - 1) * _gap;
    final centred =
        _pad +
        row * (_rowHeight + _gap) +
        _rowHeight / 2 -
        widget.viewportHeight / 2;
    _scroll = ScrollController(
      initialScrollOffset: centred.clamp(
        0.0,
        math.max(0.0, content - widget.viewportHeight),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0, 0.06, 0.94, 1],
      ).createShader(rect),
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(vertical: _pad),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          mainAxisExtent: _rowHeight,
          mainAxisSpacing: _gap,
          crossAxisSpacing: _gap,
        ),
        itemCount: _count,
        itemBuilder: (context, i) {
          final year = widget.firstYear + i;
          return _ChoicePill(
            label: '$year',
            selected: year == widget.selectedYear,
            onTap: () => widget.onYear(year),
          );
        },
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.displayed,
    required this.selected,
    required this.firstDate,
    required this.lastDate,
    required this.onDay,
  });

  final DateTime displayed;
  final DateTime selected;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loc = MaterialLocalizations.of(context);
    final firstWeekday = loc.firstDayOfWeekIndex;
    final names = loc.narrowWeekdays;
    final first = DateTime(displayed.year, displayed.month);
    final days = DateUtils.getDaysInMonth(displayed.year, displayed.month);
    final leading = (first.weekday % 7 - firstWeekday + 7) % 7;

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    names[(firstWeekday + i) % 7],
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          // Always room for six weeks, so long months are never clipped.
          child: LayoutBuilder(
            builder: (context, box) {
              final rowHeight = box.maxHeight / 6;
              final dot = math.min(
                40.0,
                math.min(rowHeight, box.maxWidth / 7) - 4,
              );
              return GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: rowHeight,
                ),
                itemCount: leading + days,
                itemBuilder: (context, i) {
                  if (i < leading) return const SizedBox.shrink();
                  final date = DateTime(
                    displayed.year,
                    displayed.month,
                    i - leading + 1,
                  );
                  return _dayCell(context, date, dot, cs);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    DateTime date,
    double size,
    ColorScheme cs,
  ) {
    final enabled = !date.isBefore(firstDate) && !date.isAfter(lastDate);
    final isSelected = date == selected;
    return Center(
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: isSelected ? cs.primary : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? () => onDay(date) : null,
            child: Center(
              child: Text(
                '${date.day}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: !enabled
                      ? cs.onSurface.withValues(alpha: 0.3)
                      : isSelected
                      ? cs.onPrimary
                      : cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
