import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum _BirthdatePage { day, month, year }

/// Birthdate calendar with a tappable month and a tappable year.
Future<DateTime?> showBirthdatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final first = DateUtils.dateOnly(firstDate);
  final last = DateUtils.dateOnly(lastDate);
  var initial = DateUtils.dateOnly(initialDate);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDialog<DateTime>(
    context: context,
    builder: (context) => _BirthdateDialog(
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    ),
  );
}

class _BirthdateDialog extends StatefulWidget {
  const _BirthdateDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_BirthdateDialog> createState() => _BirthdateDialogState();
}

class _BirthdateDialogState extends State<_BirthdateDialog> {
  late DateTime _selected = widget.initialDate;
  late DateTime _displayed = DateTime(
    widget.initialDate.year,
    widget.initialDate.month,
  );
  _BirthdatePage _page = _BirthdatePage.day;

  bool _monthInRange(int year, int month) {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1, 0);
    return !end.isBefore(widget.firstDate) && !start.isAfter(widget.lastDate);
  }

  void _showMonth(int year, int month) {
    if (!_monthInRange(year, month)) return;
    setState(() => _displayed = DateTime(year, month));
  }

  void _pickMonth(int month) {
    _jumpTo(_displayed.year, month);
  }

  void _pickYear(DateTime value) {
    _jumpTo(value.year, _displayed.month);
  }

  /// Keeps the chosen day when the month or year changes, same as the year list.
  void _jumpTo(int year, int month) {
    final end = DateTime(year, month + 1, 0);
    if (end.isBefore(widget.firstDate) ||
        DateTime(year, month).isAfter(widget.lastDate)) {
      return;
    }
    var day = _selected.day;
    if (day > end.day) day = end.day;
    var next = DateTime(year, month, day);
    if (next.isBefore(widget.firstDate)) next = widget.firstDate;
    if (next.isAfter(widget.lastDate)) next = widget.lastDate;
    setState(() {
      _selected = next;
      _displayed = DateTime(next.year, next.month);
      _page = _BirthdatePage.day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final monthLabel = DateFormat.MMMM().format(_displayed);
    final bodyHeight = (MediaQuery.sizeOf(context).height * 0.46).clamp(
      260.0,
      340.0,
    );
    final prevYear = _displayed.month == 1
        ? _displayed.year - 1
        : _displayed.year;
    final prevMonth = _displayed.month == 1 ? 12 : _displayed.month - 1;
    final nextYear = _displayed.month == 12
        ? _displayed.year + 1
        : _displayed.year;
    final nextMonth = _displayed.month == 12 ? 1 : _displayed.month + 1;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Birthdate',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Flexible(
                      child: _JumpButton(
                        label: monthLabel,
                        hint: 'Choose month',
                        expand: true,
                        open: _page == _BirthdatePage.month,
                        onTap: () => setState(() {
                          _page = _page == _BirthdatePage.month
                              ? _BirthdatePage.day
                              : _BirthdatePage.month;
                        }),
                      ),
                    ),
                    _JumpButton(
                      label: '${_displayed.year}',
                      hint: 'Choose year',
                      open: _page == _BirthdatePage.year,
                      onTap: () => setState(() {
                        _page = _page == _BirthdatePage.year
                            ? _BirthdatePage.day
                            : _BirthdatePage.year;
                      }),
                    ),
                    const Spacer(),
                    if (_page == _BirthdatePage.day) ...[
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: _monthInRange(prevYear, prevMonth)
                            ? () => _showMonth(prevYear, prevMonth)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: _monthInRange(nextYear, nextMonth)
                            ? () => _showMonth(nextYear, nextMonth)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: bodyHeight,
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
                    onMonth: _pickMonth,
                  ),
                  _BirthdatePage.year => YearPicker(
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                    selectedDate: _displayed,
                    currentDate: DateTime.now(),
                    onChanged: _pickYear,
                  ),
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JumpButton extends StatelessWidget {
  const _JumpButton({
    required this.label,
    required this.hint,
    required this.open,
    required this.onTap,
    this.expand = false,
  });

  final String label;
  final String hint;
  final bool open;
  final bool expand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: hint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (expand)
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              else
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              Icon(open ? Icons.arrow_drop_up : Icons.arrow_drop_down),
            ],
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
    final cs = Theme.of(context).colorScheme;
    final now = DateUtils.dateOnly(DateTime.now());
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.1,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (var month = 1; month <= 12; month++)
          _choice(
            context,
            label: DateFormat.MMMM().format(DateTime(year, month)),
            selected: month == selectedMonth,
            current: now.year == year && now.month == month,
            enabled: _enabled(month),
            onTap: () => onMonth(month),
            color: cs,
          ),
      ],
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
    final labels = [
      for (var i = 0; i < 7; i++) names[(firstWeekday + i) % 7],
    ];
    final first = DateTime(displayed.year, displayed.month);
    final days = DateUtils.getDaysInMonth(displayed.year, displayed.month);
    final leading = (first.weekday % 7 - firstWeekday + 7) % 7;
    final today = DateUtils.dateOnly(DateTime.now());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var day = 1; day <= days; day++)
                _dayCell(
                  context,
                  date: DateTime(displayed.year, displayed.month, day),
                  today: today,
                  color: cs,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context, {
    required DateTime date,
    required DateTime today,
    required ColorScheme color,
  }) {
    final enabled = !date.isBefore(firstDate) && !date.isAfter(lastDate);
    final isSelected = date == selected;
    final isToday = date == today;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: !enabled
          ? color.onSurface.withValues(alpha: 0.38)
          : isSelected
          ? color.onPrimary
          : color.onSurface,
    );
    return InkResponse(
      onTap: enabled ? () => onDay(date) : null,
      radius: 20,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? color.primary : null,
            shape: BoxShape.circle,
            border: isToday && !isSelected
                ? Border.all(color: color.primary)
                : null,
          ),
          child: Text('${date.day}', style: style),
        ),
      ),
    );
  }
}

Widget _choice(
  BuildContext context, {
  required String label,
  required bool selected,
  required bool current,
  required bool enabled,
  required VoidCallback onTap,
  required ColorScheme color,
}) {
  return InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? color.primary : null,
        borderRadius: BorderRadius.circular(12),
        border: current && !selected
            ? Border.all(color: color.primary)
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: !enabled
                ? color.onSurface.withValues(alpha: 0.38)
                : selected
                ? color.onPrimary
                : color.onSurface,
          ),
        ),
      ),
    ),
  );
}
