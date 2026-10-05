import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_repository.dart';
import '../../services/rental_repository.dart';

/// Current hourly fee for new rentals. Past rentals are not rewritten.
class HourlyRateCard extends StatefulWidget {
  const HourlyRateCard({super.key});

  @override
  State<HourlyRateCard> createState() => HourlyRateCardState();
}

class HourlyRateCardState extends State<HourlyRateCard> {
  final _rentals = RentalRepository();
  final _admin = AdminRepository();
  double? _rate;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  Future<void> reload() async {
    final rate = await _rentals.fetchHourlyRate();
    if (!mounted) return;
    setState(() {
      _rate = rate;
      _loading = false;
    });
  }

  String _money(double rate) {
    final whole = (rate * 100).round() % 100 == 0;
    return whole ? rate.toStringAsFixed(0) : rate.toStringAsFixed(2);
  }

  Future<void> _edit() async {
    final current = _rate ?? RentalRepository.kRatePerHour;
    final ctrl = TextEditingController(text: _money(current));
    final next = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 400),
          icon: Icon(Icons.payments_outlined, color: cs.primary),
          title: const Text('Hourly bike fee'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'New requests and the rest of an open ride use this fee. Completed rides keep the amount already saved.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Pesos per hour',
                  prefixText: '₱ ',
                ),
                onSubmitted: (_) {
                  final parsed = double.tryParse(ctrl.text.trim());
                  if (parsed != null) Navigator.of(ctx).pop(parsed);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(ctrl.text.trim());
                if (parsed == null || parsed <= 0 || parsed > 10000) return;
                Navigator.of(ctx).pop(parsed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (next == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final saved = await _admin.setHourlyRate(next);
      if (!mounted) return;
      setState(() => _rate = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hourly fee is now ₱${_money(saved)}')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError ? e.message : 'Could not save the hourly fee.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rate = _rate;
    return Material(
      color: cs.surface.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.payments_outlined, color: cs.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hourly fee',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _loading || rate == null
                        ? '…'
                        : '₱${_money(rate)} per hour',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _loading || _saving ? null : _edit,
              child: Text(_saving ? 'Saving…' : 'Change'),
            ),
          ],
        ),
      ),
    );
  }
}
