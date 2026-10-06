part of 'admin_dashboard_screen.dart';

// ── Info pair (Active rentals tab) ────────────────────────────────────────────

class _InfoPair extends StatelessWidget {
  const _InfoPair({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── Status helpers ──────────────────────────────────────────────────────────

Color _statusColor(String status, ColorScheme cs) => switch (status) {
      'available'   => const Color(0xFF22C55E),
      'rented'      => cs.primary,
      'maintenance' => cs.error,
      _             => cs.onSurfaceVariant,
    };

// ── Bike card ───────────────────────────────────────────────────────────────

class _BikeCard extends StatelessWidget {
  const _BikeCard({
    required this.bike,
    required this.onQr,
    required this.onStatusChange,
    required this.onPhotoTap,
    required this.onDelete,
  });

  final Bike bike;
  final VoidCallback onQr;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onPhotoTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _statusColor(bike.status, cs);
    final name = bike.label?.trim().isNotEmpty == true
        ? bike.label!
        : 'Bike ${bike.code}';
    final canDelete = bike.status != 'rented';

    return GlassPanel(
      radius: 20,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Colored left status bar
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Bike photo (tap to upload / replace)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onPhotoTap,
                        borderRadius: BorderRadius.circular(13),
                        child: Tooltip(
                          message: bike.hasPhoto
                              ? 'Update bike photo'
                              : 'Upload bike photo',
                          child: Stack(
                            children: [
                              BikePhotoView(
                                url: AdminRepository.publicPhotoUrl(
                                  bike.photoPath,
                                ),
                                size: 46,
                                radius: 13,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: cs.surface,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    bike.hasPhoto
                                        ? Icons.edit_rounded
                                        : Icons.add_rounded,
                                    size: 11,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    // Name + code
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Code: ${bike.code}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Right side: badge + actions
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatusBadge(status: bike.status, cs: cs),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'QR code',
                              mouseCursor: SystemMouseCursors.click,
                              icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                              onPressed: onQr,
                              style: IconButton.styleFrom(
                                foregroundColor: cs.primary,
                              ),
                            ),
                            _BikeActionsMenu(
                              status: bike.status,
                              canDelete: canDelete,
                              onStatusChange: onStatusChange,
                              onDelete: onDelete,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.cs});
  final String status;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status, cs);
    final label = status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Status filter bar ────────────────────────────────────────────────────────

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.selected, required this.onSelected});
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <(String?, String, Color)>[
      (null,          'All',         cs.primary),
      ('available',   'Available',   const Color(0xFF22C55E)),
      ('rented',      'Rented',      cs.primary),
      ('maintenance', 'Maintenance', cs.error),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final (value, label, color) = item;
        final isSelected = selected == value;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
          onTap: () => onSelected(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.12)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: isSelected ? color : cs.onSurfaceVariant,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
        );
      }).toList(),
    );
  }
}

// ── Bike actions menu (status + delete) ───────────────────────────────────────

class _BikeActionsMenu extends StatelessWidget {
  const _BikeActionsMenu({
    required this.status,
    required this.canDelete,
    required this.onStatusChange,
    required this.onDelete,
  });

  final String status;
  final bool canDelete;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A rented bike is freed by ending, rejecting, or cancelling its rental.
    final canSetStatus = status != 'rented';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: PopupMenuButton<_BikeMenuAction>(
        tooltip: 'Bike actions',
        onSelected: (action) {
          switch (action) {
            case _BikeMenuAction.available:
              onStatusChange('available');
            case _BikeMenuAction.maintenance:
              onStatusChange('maintenance');
            case _BikeMenuAction.delete:
              onDelete();
          }
        },
        icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.onSurfaceVariant),
        itemBuilder: (context) => [
          _statusItem(
            _BikeMenuAction.available,
            'Available',
            Icons.check_circle_rounded,
            const Color(0xFF22C55E),
            selected: status == 'available',
            enabled: canSetStatus,
            disabledColor: cs.onSurfaceVariant,
          ),
          _statusItem(
            _BikeMenuAction.maintenance,
            canSetStatus ? 'Maintenance' : 'End rental to change status',
            Icons.build_rounded,
            cs.error,
            selected: status == 'maintenance',
            enabled: canSetStatus,
            disabledColor: cs.onSurfaceVariant,
          ),
          const PopupMenuDivider(),
          PopupMenuItem<_BikeMenuAction>(
            value: _BikeMenuAction.delete,
            enabled: canDelete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  color: canDelete ? cs.error : cs.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  canDelete ? 'Delete bike' : 'End rental to delete',
                  style: TextStyle(
                    color: canDelete ? cs.error : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_BikeMenuAction> _statusItem(
    _BikeMenuAction value,
    String label,
    IconData icon,
    Color color, {
    required bool selected,
    required bool enabled,
    required Color disabledColor,
  }) {
    final tint = enabled ? color : disabledColor;
    return PopupMenuItem<_BikeMenuAction>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, color: tint, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          if (selected)
            Icon(Icons.check_rounded, size: 16, color: tint),
        ],
      ),
    );
  }
}

enum _BikeMenuAction { available, maintenance, delete }

// ── Empty / error states (shared) ─────────────────────────────────────────────

class _RentalDetailDialog extends StatelessWidget {
  const _RentalDetailDialog({
    required this.rental,
    required this.bike,
    required this.location,
    required this.username,
  });

  final Rental rental;
  final Bike? bike;
  final RentalLocation? location;
  final String username;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = location;
    final bikeLine = bike == null
        ? ((rental.bikeId == null || rental.bikeId!.isEmpty)
            ? 'Removed bike'
            : rental.bikeId!)
        : (bike!.label?.trim().isNotEmpty == true
            ? '${bike!.label} (${bike!.code})'
            : bike!.code);
    return AlertDialog(
      title: const Text('Rental details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bike: $bikeLine', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('Rider: $username'),
            Text(
              'Started: ${DateFormat('MMM d, h:mm a').format((rental.approvedAt ?? rental.startedAt).toLocal())}',
            ),
            const SizedBox(height: 12),
            Text(
              'Last known location',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            if (loc == null)
              const Text('No location has been recorded yet.')
            else ...[
              Text('Lat: ${loc.lat.toStringAsFixed(6)}'),
              Text('Lng: ${loc.lng.toStringAsFixed(6)}'),
              if (loc.accuracyM != null)
                Text('Accuracy: ${loc.accuracyM!.toStringAsFixed(0)} m'),
              Text(
                DateFormat('MMM d, h:mm a').format(loc.recordedAt.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(icon, size: 44, color: cs.primary),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            action,
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: cs.error),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error?.toString() ?? 'Unknown error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
