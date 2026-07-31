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

class _RiderLiveMap extends StatelessWidget {
  const _RiderLiveMap({
    required this.controller,
    required this.tracking,
    required this.onMapReady,
  });

  final MapController controller;
  final LocationTrackingService tracking;
  final VoidCallback onMapReady;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Position?>(
      valueListenable: tracking.position,
      builder: (context, pos, _) {
        final initial = pos != null
            ? LatLng(pos.latitude, pos.longitude)
            : const LatLng(14.5995, 120.9842);

        final markers = <Marker>[];
        final circles = <CircleMarker>[];

        if (pos != null) {
          final ll = LatLng(pos.latitude, pos.longitude);
          if (pos.accuracy.isFinite && pos.accuracy > 0) {
            circles.add(
              CircleMarker(
                point: ll,
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
              point: ll,
              width: 22,
              height: 22,
              child: const _UserDot(),
            ),
          );
        }

        return Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: pos != null ? 16 : 6,
                onMapReady: onMapReady,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.qride.demo',
                  maxZoom: 20,
                  retinaMode: true,
                ),
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
                    if (p != null) {
                      controller.move(LatLng(p.latitude, p.longitude), 16);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.my_location_rounded,
                        size: 18, color: Color(0xFF1A73E8)),
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

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A73E8).withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
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
                ? 'Error'
                : (shared ? 'Sharing' : 'Connecting…');
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
