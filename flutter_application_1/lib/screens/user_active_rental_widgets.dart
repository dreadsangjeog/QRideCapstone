part of 'user_active_rental_screen.dart';

class _RentalInfoRow extends StatelessWidget {
  const _RentalInfoRow({
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style:
                theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderLiveMap extends StatefulWidget {
  const _RiderLiveMap({
    required this.controller,
    required this.tracking,
    required this.onMapReady,
    required this.followUser,
    required this.onFollowChanged,
  });

  final MapController controller;
  final LocationTrackingService tracking;
  final VoidCallback onMapReady;
  final bool followUser;
  final ValueChanged<bool> onFollowChanged;

  @override
  State<_RiderLiveMap> createState() => _RiderLiveMapState();
}

class _RiderLiveMapState extends State<_RiderLiveMap> {
  SmoothLatLng? _pose;
  Timer? _tick;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    widget.tracking.position.addListener(_onPoseChanged);
    widget.tracking.heading.addListener(_onPoseChanged);
    _onPoseChanged();
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final pose = _pose;
      if (pose == null) return;
      final moved = pose.tick();
      if (!moved) return;
      if (!mounted) return;
      setState(() {});
      if (widget.followUser && _mapReady) {
        try {
          final zoom = widget.controller.camera.zoom;
          widget.controller.move(pose.current, zoom);
        } catch (_) {
          widget.controller.move(pose.current, 16);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _RiderLiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracking != widget.tracking) {
      oldWidget.tracking.position.removeListener(_onPoseChanged);
      oldWidget.tracking.heading.removeListener(_onPoseChanged);
      widget.tracking.position.addListener(_onPoseChanged);
      widget.tracking.heading.addListener(_onPoseChanged);
      _onPoseChanged();
    }
    if (!oldWidget.followUser && widget.followUser) {
      final pose = _pose;
      if (pose != null && _mapReady) {
        try {
          widget.controller.move(pose.current, widget.controller.camera.zoom);
        } catch (_) {
          widget.controller.move(pose.current, 16);
        }
      }
    }
  }

  @override
  void dispose() {
    widget.tracking.position.removeListener(_onPoseChanged);
    widget.tracking.heading.removeListener(_onPoseChanged);
    _tick?.cancel();
    super.dispose();
  }

  void _onPoseChanged() {
    final pos = widget.tracking.position.value;
    if (pos == null) return;
    final next = LatLng(pos.latitude, pos.longitude);
    final h = widget.tracking.heading.value ??
        (pos.heading >= 0 && pos.heading <= 360 ? pos.heading : null);
    _pose ??= SmoothLatLng(next);
    _pose!.setTarget(next, h);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final controller = widget.controller;
    return ValueListenableBuilder<Position?>(
      valueListenable: tracking.position,
      builder: (context, pos, _) {
        final shown = _pose?.current ??
            (pos != null
                ? LatLng(pos.latitude, pos.longitude)
                : const LatLng(14.5995, 120.9842));
        final heading = _pose?.heading ??
            tracking.heading.value ??
            (pos != null && pos.heading >= 0 ? pos.heading : 0.0);

        final markers = <Marker>[];
        final circles = <CircleMarker>[];

        if (pos != null) {
          if (pos.accuracy.isFinite && pos.accuracy > 0 && pos.accuracy < 80) {
            circles.add(
              CircleMarker(
                point: shown,
                radius: pos.accuracy,
                useRadiusInMeter: true,
                color: const Color(0x331A73E8),
                borderColor: const Color(0x661A73E8),
                borderStrokeWidth: 1,
              ),
            );
          }
          markers.add(
            Marker(
              point: shown,
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: HeadingChevron(
                headingDeg: heading,
                color: const Color(0xFF1A73E8),
                size: 20,
              ),
            ),
          );
        }

        return Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: shown,
                initialZoom: pos != null ? 16 : 6,
                onMapReady: () {
                  _mapReady = true;
                  widget.onMapReady();
                  if (widget.followUser && pos != null) {
                    controller.move(shown, 16);
                  }
                },
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture && widget.followUser) {
                    widget.onFollowChanged(false);
                  }
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                qrideStreetTiles(),
                CircleLayer(circles: circles),
                MarkerLayer(markers: markers),
              ],
            ),
            if (pos == null)
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    final p = tracking.position.value;
                    final pose = _pose;
                    widget.onFollowChanged(true);
                    final target = pose?.current ??
                        (p == null
                            ? null
                            : LatLng(p.latitude, p.longitude));
                    if (target != null) {
                      try {
                        controller.move(target, controller.camera.zoom);
                      } catch (_) {
                        controller.move(target, 16);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 18,
                      color: widget.followUser
                          ? const Color(0xFF1A73E8)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GpsStatusBadge extends StatelessWidget {
  const _GpsStatusBadge({required this.tracking});
  final LocationTrackingService tracking;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: tracking.lastError,
      builder: (context, err, _) {
        return ValueListenableBuilder<DateTime?>(
          valueListenable: tracking.lastWriteAt,
          builder: (context, writeAt, _) {
            final hasError = err != null;
            final shared = writeAt != null;
            final color = hasError
                ? cs.error
                : (shared ? const Color(0xFF22C55E) : cs.onSurfaceVariant);
            final label = hasError
                ? 'Not reaching admin'
                : (shared ? 'Sharing with admin' : 'Connecting…');
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _GpsDetailRow extends StatefulWidget {
  const _GpsDetailRow({required this.tracking});
  final LocationTrackingService tracking;

  @override
  State<_GpsDetailRow> createState() => _GpsDetailRowState();
}

class _GpsDetailRowState extends State<_GpsDetailRow> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  String _formatAgo(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 5) return 'just now';
    if (s < 60) return '${s}s ago';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ago';
    return '${m ~/ 60}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String?>(
      valueListenable: widget.tracking.lastError,
      builder: (context, err, _) {
        if (err != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: cs.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  err,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          );
        }
        return ValueListenableBuilder<DateTime?>(
          valueListenable: widget.tracking.lastWriteAt,
          builder: (context, writeAt, _) {
            return ValueListenableBuilder<Position?>(
              valueListenable: widget.tracking.position,
              builder: (context, pos, _) {
                final accuracy = pos?.accuracy;
                final accText = accuracy == null
                    ? ''
                    : ' · GPS ±${accuracy.toStringAsFixed(0)}m';
                final text = writeAt == null
                    ? 'Waiting for first GPS fix to share with admin…$accText'
                    : 'Shared ${_formatAgo(writeAt)} · '
                        '${DateFormat('h:mm:ss a').format(writeAt.toLocal())}'
                        '$accText';
                return Row(
                  children: [
                    Icon(
                      writeAt == null
                          ? Icons.hourglass_empty_rounded
                          : Icons.cloud_done_outlined,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  final String label;
  final double value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          )
        : theme.textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('₱${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

class _ExtendTimeSheet extends StatefulWidget {
  const _ExtendTimeSheet({
    required this.currentPlannedMinutes,
    required this.ratePerHour,
  });

  final int currentPlannedMinutes;
  final double ratePerHour;

  @override
  State<_ExtendTimeSheet> createState() => _ExtendTimeSheetState();
}

class _ExtendTimeSheetState extends State<_ExtendTimeSheet> {
  static const _presets = [
    (label: '15 min', minutes: 15),
    (label: '30 min', minutes: 30),
    (label: '1 hour', minutes: 60),
    (label: '2 hours', minutes: 120),
  ];

  int _extraMinutes = 15;

  double get _extraCost => (_extraMinutes / 60.0) * widget.ratePerHour;

  int get _newTotalMinutes => widget.currentPlannedMinutes + _extraMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Text(
            'Extend rental time',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Minimum extension is 15 minutes. Extra time is billed at the same hourly rate.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              final selected = _extraMinutes == p.minutes;
              return ChoiceChip(
                label: Text(p.label),
                selected: selected,
                onSelected: (_) => setState(() => _extraMinutes = p.minutes),
                selectedColor: cs.primary,
                labelStyle: TextStyle(
                  color: selected ? cs.onPrimary : cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Added cost',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      '₱${_extraCost.toStringAsFixed(2)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'New booked duration',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      _newTotalMinutes >= 60
                          ? '${_newTotalMinutes ~/ 60}h '
                              '${_newTotalMinutes % 60 > 0 ? "${_newTotalMinutes % 60}m" : ""}'
                                  .trim()
                          : '${_newTotalMinutes}m',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () => Navigator.of(context).pop(_extraMinutes),
            icon: const Icon(Icons.more_time_rounded),
            label: Text('Extend by $_extraMinutes min'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
