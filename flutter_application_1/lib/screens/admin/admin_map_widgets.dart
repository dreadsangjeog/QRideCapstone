part of 'admin_map_tab.dart';

// ── Status card overlay ───────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.riderCount,
    required this.liveCount,
    required this.delayedCount,
    required this.staleCount,
    required this.lastRefresh,
    required this.loading,
    required this.hasAdminGps,
    required this.onRefresh,
    required this.onCenterAdmin,
  });

  final int riderCount;
  final int liveCount;
  final int delayedCount;
  final int staleCount;
  final DateTime? lastRefresh;
  final bool loading;
  final bool hasAdminGps;
  final VoidCallback onRefresh;
  final VoidCallback? onCenterAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tf = lastRefresh != null
        ? DateFormat('h:mm:ss a').format(lastRefresh!.toLocal())
        : null;

    String title;
    if (riderCount == 0) {
      title = 'No active riders';
    } else if (staleCount == 0 && delayedCount == 0) {
      title = '$liveCount rider${liveCount == 1 ? '' : 's'} sharing location';
    } else if (liveCount == 0 && delayedCount == 0) {
      title = '$staleCount rider${staleCount == 1 ? '' : 's'} not updating';
    } else if (staleCount == 0) {
      title = '$liveCount sharing · $delayedCount delayed';
    } else {
      title = '$liveCount sharing · $staleCount not updating';
    }

    return GlassPanel(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: liveCount > 0
                    ? cs.error
                    : staleCount > 0
                    ? cs.outline
                    : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (tf != null)
                    Text(
                      'Map checked $tf',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  if (!hasAdminGps)
                    Text(
                      'Waiting for your GPS…',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (onCenterAdmin != null)
                IconButton(
                  tooltip: 'My location',
                  onPressed: onCenterAdmin,
                  icon: const Icon(Icons.my_location_rounded),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                tooltip: 'Refresh riders',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
    );
  }
}

// ── Legend ────────────────────────────────────────────────────────────────────

class _Legend extends StatelessWidget {
  const _Legend({required this.errorColor});

  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassPanel(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _LegendRow(color: const Color(0xFF1A73E8), label: 'You (admin)'),
            const SizedBox(height: 4),
            _LegendRow(color: errorColor, label: 'Sharing location'),
            const SizedBox(height: 4),
            _LegendRow(color: const Color(0xFFF59E0B), label: 'Update delayed'),
            const SizedBox(height: 4),
            _LegendRow(color: cs.outline, label: 'Last known point'),
          ],
        ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ── Bottom-sheet detail row ───────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Riders list sheet ─────────────────────────────────────────────────────────

class _RidersListSheet extends StatefulWidget {
  const _RidersListSheet({
    required this.riders,
    required this.loading,
    required this.scrollController,
    required this.onRefresh,
    required this.onLocate,
    required this.onDetails,
    this.onClose,
  });

  final List<_MarkerRow> riders;
  final bool loading;
  final ScrollController scrollController;
  final VoidCallback onRefresh;
  final VoidCallback? onClose;
  final ValueChanged<_MarkerRow> onLocate;
  final ValueChanged<_MarkerRow> onDetails;

  @override
  State<_RidersListSheet> createState() => _RidersListSheetState();
}

class _RidersListSheetState extends State<_RidersListSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_MarkerRow> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.riders;
    return widget.riders.where((r) {
      return r.username.toLowerCase().contains(q) ||
          r.bikeCode.toLowerCase().contains(q) ||
          r.bikeLabel.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
          child: Row(
            children: [
              Icon(Icons.people_alt_rounded, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Active riders',
                style:
                    (widget.onClose != null
                            ? theme.textTheme.titleMedium
                            : theme.textTheme.titleLarge)
                        ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.riders.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: widget.onRefresh,
                icon: widget.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Hide panel',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search rider, bike code, or label…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 14,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _RidersListEmpty(
                  query: _query,
                  hasRiders: widget.riders.isNotEmpty,
                  scrollController: widget.scrollController,
                )
              : ListView.separated(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final r = filtered[index];
                    return Material(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => widget.onLocate(r),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: switch (r.signal) {
                                    _RiderSignal.live => cs.errorContainer,
                                    _RiderSignal.delayed => const Color(
                                      0x14F59E0B,
                                    ),
                                    _ => cs.surfaceContainerHighest,
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  switch (r.signal) {
                                    _RiderSignal.live =>
                                      Icons.directions_bike_rounded,
                                    _RiderSignal.delayed =>
                                      Icons.schedule_rounded,
                                    _ => Icons.location_off_outlined,
                                  },
                                  color: switch (r.signal) {
                                    _RiderSignal.live => cs.onErrorContainer,
                                    _RiderSignal.delayed =>
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFFB45309),
                                    _ => cs.onSurfaceVariant,
                                  },
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.username,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${r.bikeLabel} · ${r.bikeCode}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      r.freshnessLabel,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: switch (r.signal) {
                                              _RiderSignal.live => const Color(
                                                0xFF34C759,
                                              ),
                                              _RiderSignal.delayed =>
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? const Color(0xFFFBBF24)
                                                    : const Color(0xFFB45309),
                                              _ => cs.error,
                                            },
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Column(
                                children: [
                                  IconButton(
                                    tooltip: 'Locate',
                                    onPressed: () => widget.onLocate(r),
                                    icon: const Icon(Icons.my_location_rounded),
                                    color: cs.primary,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    tooltip: 'Details',
                                    onPressed: () => widget.onDetails(r),
                                    icon: const Icon(
                                      Icons.info_outline_rounded,
                                    ),
                                    color: cs.onSurfaceVariant,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RidersListEmpty extends StatelessWidget {
  const _RidersListEmpty({
    required this.query,
    required this.hasRiders,
    required this.scrollController,
  });

  final String query;
  final bool hasRiders;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSearching = query.trim().isNotEmpty;
    return ListView(
      controller: scrollController,
      children: [
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(
                isSearching
                    ? Icons.search_off_rounded
                    : Icons.directions_bike_outlined,
                size: 48,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                isSearching
                    ? 'No matching riders'
                    : (hasRiders ? 'No riders' : 'No active riders'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  isSearching
                      ? 'Try a different search term, bike code, or rider name.'
                      : 'Approved rentals with shared GPS will appear here.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
