import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/rental.dart';
import '../../models/rental_with_bike.dart';
import '../../services/admin_repository.dart';
import '../../services/rental_repository.dart';
import '../../utils/peso.dart';
import '../../utils/rental_billing.dart';
import '../../widgets/qride_glass.dart';
import 'admin_layout.dart';

typedef _BillingOutcome = ({double penalty, double total});

/// Admin view of all rentals: who requested which bike and current/historical outcome.
class AdminHistoryTab extends StatefulWidget {
  const AdminHistoryTab({super.key, required this.repo, this.changes});

  final AdminRepository repo;
  final Listenable? changes;

  @override
  State<AdminHistoryTab> createState() => _AdminHistoryTabState();
}

class _AdminHistoryTabState extends State<AdminHistoryTab>
    with AdminSilentReload, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static const _filters = <({String label, String? status})>[
    (label: 'All', status: null),
    (label: 'Ended', status: 'ended'),
    (label: 'Active', status: 'active'),
    (label: 'Pending', status: 'pending'),
  ];

  String? _statusFilter;
  List<RentalWithBike>? _rows;
  List<HourlyRateChange> _rateHistory = const [];
  Object? _error;
  Timer? _poll;
  Timer? _clock;
  Timer? _coalesce;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_onLive);
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _onLive());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final rows = _rows;
      if (rows == null || rows.isEmpty) return;
      final needsTick = rows.any((r) => r.rental.isActive || r.rental.isPending);
      if (needsTick) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant AdminHistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes?.removeListener(_onLive);
      widget.changes?.addListener(_onLive);
    }
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_onLive);
    _poll?.cancel();
    _clock?.cancel();
    _coalesce?.cancel();
    super.dispose();
  }

  void _onLive() {
    _coalesce?.cancel();
    _coalesce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<List<RentalWithBike>> _load() =>
      widget.repo.fetchRentalsHistory(status: _statusFilter);

  Future<void> _refresh() async {
    await silentReload(() async {
      try {
        final rowsFuture = _load();
        final historyFuture = RentalRepository().fetchRateHistory();
        final rows = await rowsFuture;
        final history = await historyFuture;
        if (!mounted) return;
        setState(() {
          _rows = rows;
          _rateHistory = history;
          _error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          if (_rows == null) _error = e;
        });
      }
    });
  }

  Future<void> _editEndedBilling(RentalWithBike row) async {
    final result = await showDialog<_BillingOutcome>(
      context: context,
      builder: (ctx) => _AdjustEndedBillingDialog(
        row: row,
        history: _rateHistory,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await widget.repo.adjustEndedRentalBilling(
        rentalId: row.rental.id,
        actualCost: result.total,
        penaltyFee: result.penalty,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Billing updated')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final df = DateFormat('MMM d, yyyy · h:mm a');

    final pad = adminPagePadding(context);
    return AdminContent(
      maxWidth: 1080,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminPageHeader(
                title: 'Rental history',
                subtitle:
                    'Most recent activity first · an ended ride is ordered by when it ended, not when it was requested',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _filters)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _statusFilter == f.status,
                      onSelected: (selected) {
                        if (!selected) return;
                        setState(() {
                          _statusFilter = f.status;
                          _rows = null;
                          _error = null;
                        });
                        unawaited(_refresh());
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _historyBody(context, theme, cs, df, pad),
          ),
        ),
      ],
      ),
    );
  }

  Widget _historyBody(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    DateFormat df,
    EdgeInsets pad,
  ) {
    if (_rows == null && _error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.error_outline, size: 48, color: cs.error),
          const SizedBox(height: 12),
          Text(_error.toString()),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }
    if (_rows == null) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    final rows = _rows!;
    if (rows.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: 280,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 56,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No rentals match this filter.',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, pad.bottom),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _HistoryRentalCard(
        key: ValueKey(rows[i].rental.id),
        row: rows[i],
        dateFmt: df,
        rateHistory: _rateHistory,
        onEndedTap: () => _editEndedBilling(rows[i]),
        onActiveHint: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'End active rentals from the Active tab so times and fees stay accurate.',
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryRentalCard extends StatefulWidget {
  const _HistoryRentalCard({
    super.key,
    required this.row,
    required this.dateFmt,
    required this.rateHistory,
    required this.onEndedTap,
    required this.onActiveHint,
  });

  final RentalWithBike row;
  final DateFormat dateFmt;
  final List<HourlyRateChange> rateHistory;
  final VoidCallback onEndedTap;
  final VoidCallback onActiveHint;

  @override
  State<_HistoryRentalCard> createState() => _HistoryRentalCardState();
}

class _HistoryRentalCardState extends State<_HistoryRentalCard> {
  bool _expanded = false;

  Color _statusColor(String status, ColorScheme cs) {
    final dark = cs.brightness == Brightness.dark;
    return switch (status) {
        'ended' => dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
        'active' => cs.primary,
        'pending' => dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
        'rejected' => cs.error,
        _ => cs.onSurfaceVariant,
      };
  }

  String _statusLabel(String status) => switch (status) {
        'ended' => 'Ended',
        'active' => 'Active',
        'pending' => 'Pending',
        'rejected' => 'Rejected',
        _ => status,
      };

  String _compactSummary({
    required Rental r,
    required double? otMin,
    required double? storedTotal,
    required double? totalSuggested,
    double? rideMinutes,
  }) {
    final dfShort = DateFormat('MMM d, h:mm a');
    switch (r.status) {
      case 'ended':
        final end = r.endedAt != null ? dfShort.format(r.endedAt!.toLocal()) : '—';
        final ot =
            otMin != null && otMin > 0 ? '${otMin.ceil()}m OT' : 'On time';
        final money = storedTotal != null
            ? '₱${storedTotal.toStringAsFixed(0)}'
            : (totalSuggested != null
                ? '~₱${totalSuggested.toStringAsFixed(0)}'
                : '—');
        return '$end · $ot · $money';
      case 'active':
        final ride = rideMinutes != null
            ? formatRideDurationMinutes(rideMinutes)
            : '—';
        final ot =
            otMin != null && otMin > 0 ? '${otMin.ceil()}m OT' : 'Within plan';
        return '$ride · $ot';
      case 'pending':
        return 'Requested ${dfShort.format(r.startedAt.toLocal())}';
      case 'rejected':
        return 'Rejected';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = widget.row;
    final r = row.rental;
    final dateFmt = widget.dateFmt;
    final statusColor = _statusColor(r.status, cs);

    final approvedStart = r.approvedAt ?? r.startedAt;
    final endOrNow = r.endedAt ?? DateTime.now();
    final hasRideWindow = r.approvedAt != null || r.status != 'pending';

    double? elapsedMin;
    double? otMin;
    double? base;
    double? penSuggested;
    double? totalSuggested;
    if (hasRideWindow && r.status != 'rejected') {
      elapsedMin = rideElapsedMinutes(r, endOrNow);
      final ot = overtimeMinutesAt(r, endOrNow);
      otMin = ot;
      final charge = rentalChargeAt(r, endOrNow, widget.rateHistory);
      base = charge.base;
      penSuggested = charge.penalty;
      totalSuggested = charge.total;
    }

    final storedPen = r.penaltyFee;
    final storedTotal = r.actualCost;
    final showDbBilling = r.status == 'ended';

    return GlassPanel(
      radius: 20,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    row.accountDeleted
                        ? Icons.person_off_outlined
                        : Icons.person_outline_rounded,
                    size: 22,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.riderDisplay,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      if (row.accountDeleted &&
                          row.riderDisplay != 'Deleted account') ...[
                        const SizedBox(height: 2),
                        Text(
                          'Deleted account',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ] else if (row.riderUsername != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          row.riderUsername!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        row.bikeDisplay,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _compactSummary(
                          r: r,
                          otMin: otMin,
                          storedTotal: storedTotal,
                          totalSuggested: totalSuggested,
                          rideMinutes: elapsedMin,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: otMin != null && otMin > 0
                              ? cs.error
                              : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        _statusLabel(r.status),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.status == 'ended')
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Adjust billing',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                            padding: EdgeInsets.zero,
                            onPressed: widget.onEndedTap,
                          ),
                        IconButton(
                          icon: Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 22,
                          ),
                          tooltip: _expanded ? 'Hide details' : 'All details',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 1,
                          color:
                              cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 10),
                        _Line(
                          icon: Icons.schedule_rounded,
                          label: 'Requested',
                          value: dateFmt.format(r.startedAt.toLocal()),
                        ),
                        if (r.approvedAt != null) ...[
                          const SizedBox(height: 6),
                          _Line(
                            icon: Icons.verified_outlined,
                            label: 'Approved',
                            value: dateFmt.format(r.approvedAt!.toLocal()),
                          ),
                        ],
                        if (r.approvedAt != null) ...[
                          const SizedBox(height: 6),
                          _Line(
                            icon: Icons.event_available_outlined,
                            label: 'Planned end',
                            value: dateFmt.format(
                              approvedStart
                                  .add(Duration(minutes: r.plannedMinutes))
                                  .toLocal(),
                            ),
                          ),
                        ],
                        if (r.endedAt != null) ...[
                          const SizedBox(height: 6),
                          _Line(
                            icon: Icons.flag_rounded,
                            label: 'Ended',
                            value: dateFmt.format(r.endedAt!.toLocal()),
                          ),
                        ],
                        if (elapsedMin != null &&
                            base != null &&
                            otMin != null &&
                            penSuggested != null &&
                            totalSuggested != null) ...[
                          const SizedBox(height: 6),
                          _Line(
                            icon: Icons.directions_bike_outlined,
                            label: r.status == 'active'
                                ? 'Ride so far'
                                : 'Ride duration',
                            value: formatRideDurationMinutes(elapsedMin),
                          ),
                          const SizedBox(height: 6),
                          _Line(
                            icon: otMin > 0
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                            label: 'Overtime',
                            valueColor: otMin > 0
                                ? cs.error
                                : (cs.brightness == Brightness.dark
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFF16A34A)),
                            value: otMin > 0
                                ? '${otMin.ceil()} min beyond plan'
                                : 'None (on time or early)',
                          ),
                          const SizedBox(height: 6),
                          _Line(
                            icon: Icons.payments_outlined,
                            label: 'Base (planned slot)',
                            value: formatPeso(base),
                          ),
                          if (showDbBilling &&
                              (storedPen != null ||
                                  storedTotal != null)) ...[
                            const SizedBox(height: 6),
                            _Line(
                              icon: Icons.receipt_long_outlined,
                              label: 'Penalty (saved)',
                              value: formatPeso(storedPen ?? 0),
                            ),
                            const SizedBox(height: 6),
                            _Line(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Total (saved)',
                              value: storedTotal != null
                                  ? formatPeso(storedTotal)
                                  : '—',
                              valueColor: storedTotal == null
                                  ? cs.onSurfaceVariant
                                  : null,
                            ),
                          ] else ...[
                            const SizedBox(height: 6),
                            _Line(
                              icon: Icons.calculate_outlined,
                              label: 'From clock (suggested)',
                              value:
                                  'Penalty ${formatPeso(penSuggested)} · Total ${formatPeso(totalSuggested)}',
                              valueColor: cs.onSurfaceVariant,
                            ),
                          ],
                        ],
                        const SizedBox(height: 6),
                        _Line(
                          icon: Icons.timer_outlined,
                          label: 'Plan',
                          value:
                              '${r.plannedMinutes ~/ 60}h ${r.plannedMinutes % 60}m  ·  ₱${r.ratePerHour.toStringAsFixed(0)}/hr',
                        ),
                        if (r.status == 'active') ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: widget.onActiveHint,
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: const Text(
                                'End from Active tab',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final valStyle = valueColor ?? cs.onSurface;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface),
              children: [
                TextSpan(
                  text: '$label · ',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: TextStyle(color: valStyle, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdjustEndedBillingDialog extends StatefulWidget {
  const _AdjustEndedBillingDialog({
    required this.row,
    required this.history,
  });

  final RentalWithBike row;
  final List<HourlyRateChange> history;

  @override
  State<_AdjustEndedBillingDialog> createState() =>
      _AdjustEndedBillingDialogState();
}

class _AdjustEndedBillingDialogState extends State<_AdjustEndedBillingDialog> {
  late final TextEditingController _penalty;
  late final TextEditingController _total;
  String? _error;

  Rental get r => widget.row.rental;

  @override
  void initState() {
    super.initState();
    final end = r.endedAt!;
    final charge = rentalChargeAt(r, end, widget.history);
    _penalty = TextEditingController(
      text: roundPeso(r.penaltyFee ?? charge.penalty).toStringAsFixed(0),
    );
    _total = TextEditingController(
      text: roundPeso(r.actualCost ?? charge.total).toStringAsFixed(0),
    );
    _penalty.addListener(_syncTotalFromPenalty);
  }

  void _syncTotalFromPenalty() {
    final p = double.tryParse(_penalty.text.trim().replaceAll(',', ''));
    if (p == null || p < 0) return;
    final next = roundPeso(_clockCharge.base + p).toStringAsFixed(0);
    if (_total.text == next) return;
    _total.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  void dispose() {
    _penalty.dispose();
    _total.dispose();
    super.dispose();
  }

  RentalCharge get _clockCharge =>
      rentalChargeAt(r, r.endedAt!, widget.history);

  void _applySuggestedFromClock() {
    final charge = _clockCharge;
    setState(() {
      _error = null;
      _penalty.text = charge.penalty.toStringAsFixed(0);
      _total.text = charge.total.toStringAsFixed(0);
    });
  }

  void _trySave() {
    final base = _clockCharge.base;
    final p = double.tryParse(_penalty.text.trim().replaceAll(',', ''));
    final t = double.tryParse(_total.text.trim().replaceAll(',', ''));
    if (p == null || t == null) {
      setState(() => _error = 'Enter valid numbers for penalty and total.');
      return;
    }
    if (p < 0 || t < 0) {
      setState(() => _error = 'Amounts cannot be negative.');
      return;
    }
    if (t + 0.009 < base) {
      setState(
        () => _error =
            'Total is below base slot charge (${formatPeso(base)}).',
      );
      return;
    }
    Navigator.pop(context, (penalty: roundPeso(p), total: roundPeso(t)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final end = r.endedAt!;
    final charge = _clockCharge;
    final base = charge.base;
    final ot = overtimeMinutesAt(r, end);
    final sugPen = charge.penalty;

    return AlertDialog(
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
      title: const Text('Adjust billing'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.row.riderDisplay,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (widget.row.accountDeleted &&
                widget.row.riderDisplay != 'Deleted account')
              Text(
                'Deleted account',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              )
            else if (widget.row.riderUsername != null)
              Text(
                widget.row.riderUsername!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            Text(
              widget.row.bikeDisplay,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text('Overtime from times: ${ot.ceil()} min'),
            Text('Base slot charge: ${formatPeso(base)}'),
            Text(
              'Formula penalty (1.5× hourly rate): ${formatPeso(sugPen)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _penalty,
              decoration: const InputDecoration(
                labelText: 'Penalty (₱)',
                border: OutlineInputBorder(),
                prefixText: '₱ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _total,
              decoration: const InputDecoration(
                labelText: 'Total charged (₱)',
                border: OutlineInputBorder(),
                prefixText: '₱ ',
                helperText:
                    'Updates to base + penalty. You can still type a different total.',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _applySuggestedFromClock,
                child: const Text('Reset from ride times'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _trySave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
