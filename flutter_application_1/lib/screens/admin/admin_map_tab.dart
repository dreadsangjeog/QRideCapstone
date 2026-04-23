import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../services/admin_repository.dart';

class AdminMapTab extends StatefulWidget {
  const AdminMapTab({super.key, required this.repo});

  final AdminRepository repo;

  @override
  State<AdminMapTab> createState() => _AdminMapTabState();
}

class _AdminMapTabState extends State<AdminMapTab> {
  final _mapController = MapController();
  late Future<List<_AdminMarkerRow>> _future = _load();
  Timer? _timer;

  Future<List<_AdminMarkerRow>> _load() async {
    final rows = await widget.repo.fetchActiveRentalLastLocationsJoined();
    return rows.map(_AdminMarkerRow.fromJoined).where((e) => e != null).cast<_AdminMarkerRow>().toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  @override
  void initState() {
    super.initState();
    // Lightweight "live" refresh for admin monitoring.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<_AdminMarkerRow>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              children: const [
                SizedBox(height: 160),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.error_outline, size: 56, color: cs.error),
                const SizedBox(height: 10),
                Text(
                  'Could not load map data',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot.error.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            );
          }

          final items = snapshot.data ?? const <_AdminMarkerRow>[];
          if (items.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.map_outlined, size: 56, color: cs.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'No live locations',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Start a rental and ensure the rider app is sending GPS updates. '
                  'Then refresh.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            );
          }

          final center = LatLng(items.first.lat, items.first.lng);
          final markers = items.map((e) {
            return Marker(
              width: 44,
              height: 44,
              point: LatLng(e.lat, e.lng),
              child: GestureDetector(
                onTap: () => _showDetails(e),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      e.bikeCode,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Live bike locations',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Re-center',
                        onPressed: () {
                          _mapController.move(center, 15);
                        },
                        icon: const Icon(Icons.my_location_outlined),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 420,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 15,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.qride',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tap a marker for details. Auto-refresh every 15 seconds.',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDetails(_AdminMarkerRow row) async {
    final df = DateFormat('MMM d, h:mm a');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                row.bikeLabel,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Bike code: ${row.bikeCode}',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text('Lat: ${row.lat.toStringAsFixed(6)}'),
              Text('Lng: ${row.lng.toStringAsFixed(6)}'),
              if (row.recordedAt != null)
                Text(
                  'Updated: ${df.format(row.recordedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _mapController.move(LatLng(row.lat, row.lng), 17);
                },
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Center on bike'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminMarkerRow {
  _AdminMarkerRow({
    required this.rentalId,
    required this.bikeCode,
    required this.bikeLabel,
    required this.lat,
    required this.lng,
    required this.recordedAt,
  });

  final String rentalId;
  final String bikeCode;
  final String bikeLabel;
  final double lat;
  final double lng;
  final DateTime? recordedAt;

  static _AdminMarkerRow? fromJoined(Map<String, dynamic> json) {
    try {
      final rentals = json['rentals'] as Map<String, dynamic>?;
      final bikes = rentals?['bikes'] as Map<String, dynamic>?;
      final code = (bikes?['code'] ?? '').toString();
      if (code.trim().isEmpty) return null;

      final label = (bikes?['label'] ?? '').toString().trim();
      return _AdminMarkerRow(
        rentalId: json['rental_id'].toString(),
        bikeCode: code,
        bikeLabel: label.isEmpty ? 'Bike $code' : label,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        recordedAt: json['recorded_at'] == null
            ? null
            : DateTime.tryParse(json['recorded_at'].toString()),
      );
    } catch (_) {
      return null;
    }
  }
}

