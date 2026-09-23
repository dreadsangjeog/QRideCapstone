import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/admin_repository.dart';
import '../../services/notification_repository.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_client.dart';
import '../../widgets/heading_map_pin.dart';
import '../../widgets/qride_map_tiles.dart';

part 'admin_map_models.dart';
part 'admin_map_widgets.dart';

class AdminMapTab extends StatefulWidget {
  const AdminMapTab({super.key, required this.repo});

  final AdminRepository repo;

  @override
  State<AdminMapTab> createState() => _AdminMapTabState();
}

class _AdminMapTabState extends State<AdminMapTab> {
  final _mapController = MapController();

  Position? _adminPos;
  StreamSubscription<Position>? _locationSub;
  bool _centeredOnAdmin = false;

  List<_MarkerRow> _riders = [];
  final Map<String, SmoothLatLng> _poses = {};
  bool _loadingRiders = false;
  DateTime? _lastRefresh;
  Timer? _refreshTimer;
  Timer? _smoothTimer;
  Timer? _staleTimer;
  RealtimeChannel? _locationChannel;
  final Set<String> _offlineNotified = {};
  final _notifRepo = NotificationRepository();

  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _startAdminLocation();
    _loadRiders();
    _subscribeRiderLocations();
    _smoothTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
      var moved = false;
      for (final p in _poses.values) {
        if (p.tick()) moved = true;
      }
      if (moved && mounted) setState(() {});
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        if (mounted) _loadRiders(silent: true);
      },
    );
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _notifyNewlyOffline();
    });
  }

  void _subscribeRiderLocations() {
    _locationChannel = SupabaseClientProvider.client
        .channel('admin-rider-locations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rental_last_location',
          callback: (_) {
            if (mounted) _loadRiders(silent: true);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _refreshTimer?.cancel();
    _smoothTimer?.cancel();
    _staleTimer?.cancel();
    _locationChannel?.unsubscribe();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startAdminLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() => _adminPos = pos);
      _centerOnAdmin(pos);
    } catch (_) {}

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _adminPos = pos);
      if (!_centeredOnAdmin) _centerOnAdmin(pos);
    });
  }

  void _centerOnAdmin(Position pos) {
    if (!_mapReady) return;
    _centeredOnAdmin = true;
    _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
  }

  Future<void> _loadRiders({bool silent = false}) async {
    if (!silent) setState(() => _loadingRiders = true);
    try {
      final rows = await widget.repo.fetchActiveRentalLastLocationsJoined();
      final parsed = rows
          .map(_MarkerRow.fromJoined)
          .whereType<_MarkerRow>()
          .toList();
      if (!mounted) return;
      final ids = parsed.map((r) => r.rentalId).toSet();
      for (final r in parsed) {
        final pose = _poses.putIfAbsent(
          r.rentalId,
          () => SmoothLatLng(LatLng(r.lat, r.lng)),
        );
        pose.setTarget(LatLng(r.lat, r.lng), r.heading);
      }
      _poses.removeWhere((id, _) => !ids.contains(id));
      _offlineNotified.removeWhere((id) => !ids.contains(id));
      setState(() {
        _riders = parsed;
        _loadingRiders = false;
        _lastRefresh = DateTime.now();
      });
      _notifyNewlyOffline();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRiders = false);
    }
  }

  void _notifyNewlyOffline() {
    for (final r in _riders) {
      if (!r.isStale) {
        _offlineNotified.remove(r.rentalId);
        continue;
      }
      if (!_offlineNotified.add(r.rentalId)) continue;
      final body =
          '${r.username} on ${r.bikeLabel} lost signal. Last point is still on the map.';
      unawaited(
        _notifRepo.notifyAdmins(
          type: 'rider_offline',
          title: 'Rider lost signal',
          body: body,
          data: {'rental_id': r.rentalId, 'username': r.username},
        ),
      );
      unawaited(
        NotificationService.showInboxBanner(
          AppNotification(
            id: 'local-offline-${r.rentalId}',
            userId: '',
            roleScope: 'admin',
            type: 'rider_offline',
            title: 'Rider lost signal',
            body: body,
            data: const {},
            createdAt: DateTime.now().toUtc(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final initialCenter = _adminPos != null
        ? LatLng(_adminPos!.latitude, _adminPos!.longitude)
        : const LatLng(14.5995, 120.9842);

    final liveCount = _riders.where((r) => !r.isStale).length;
    final staleCount = _riders.length - liveCount;

    final riderMarkers = _poses.entries.map((e) {
      _MarkerRow? row;
      for (final r in _riders) {
        if (r.rentalId == e.key) {
          row = r;
          break;
        }
      }
      final stale = row?.isStale ?? true;
      return Marker(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        point: e.value.current,
        child: GestureDetector(
          onTap: row == null ? null : () => _showRiderDetails(row!),
          child: Opacity(
            opacity: stale ? 0.55 : 1,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                HeadingChevron(
                  headingDeg: e.value.heading,
                  color: stale ? cs.outline : cs.error,
                  size: 20,
                ),
                if (stale)
                  const Positioned(
                    right: -2,
                    top: -2,
                    child: Icon(
                      Icons.signal_wifi_off_rounded,
                      size: 10,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    final adminCircles = _adminPos != null
        ? [
            CircleMarker(
              point: LatLng(_adminPos!.latitude, _adminPos!.longitude),
              radius: _adminPos!.accuracy,
              useRadiusInMeter: true,
              color: const Color(0xFF1A73E8).withValues(alpha: 0.15),
              borderColor: const Color(0xFF1A73E8).withValues(alpha: 0.4),
              borderStrokeWidth: 1.5,
            ),
          ]
        : <CircleMarker>[];

    final adminMarkers = _adminPos != null
        ? [
            Marker(
              width: 24,
              height: 24,
              point: LatLng(_adminPos!.latitude, _adminPos!.longitude),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1A73E8),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x441A73E8),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ]
        : <Marker>[];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 15,
            onMapReady: () {
              _mapReady = true;
              if (_adminPos != null && !_centeredOnAdmin) {
                _centerOnAdmin(_adminPos!);
              }
            },
          ),
          children: [
            qrideStreetTiles(),
            CircleLayer(circles: adminCircles),
            MarkerLayer(markers: riderMarkers),
            MarkerLayer(markers: adminMarkers),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _StatusCard(
            riderCount: _riders.length,
            liveCount: liveCount,
            staleCount: staleCount,
            lastRefresh: _lastRefresh,
            loading: _loadingRiders,
            hasAdminGps: _adminPos != null,
            onRefresh: () => _loadRiders(),
            onCenterAdmin: _adminPos == null
                ? null
                : () => _mapController.move(
                      LatLng(_adminPos!.latitude, _adminPos!.longitude),
                      16,
                    ),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 12,
          child: _Legend(errorColor: cs.error),
        ),
        Positioned(
          bottom: 16,
          right: 12,
          child: FloatingActionButton.extended(
            heroTag: 'admin-map-riders-fab',
            onPressed: _showRidersList,
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            elevation: 4,
            icon: const Icon(Icons.people_alt_rounded),
            label: Text(
              _riders.isEmpty
                  ? 'Riders'
                  : '${_riders.length} rider${_riders.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showRidersList() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollController) => _RidersListSheet(
            riders: _riders,
            loading: _loadingRiders,
            scrollController: scrollController,
            onRefresh: () => _loadRiders(),
            onLocate: (rider) {
              Navigator.of(sheetCtx).pop();
              _mapController.move(LatLng(rider.lat, rider.lng), 17);
            },
            onDetails: (rider) {
              Navigator.of(sheetCtx).pop();
              _showRiderDetails(rider);
            },
          ),
        );
      },
    );
  }

  Future<void> _showRiderDetails(_MarkerRow row) async {
    final df = DateFormat('MMM d, h:mm a');
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.directions_bike_rounded,
                      color: cs.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.bikeLabel,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          row.bikeCode,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                icon: Icons.person_outline_rounded,
                label: 'Rider',
                value: row.username,
              ),
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Coordinates',
                value:
                    '${row.lat.toStringAsFixed(6)}, ${row.lng.toStringAsFixed(6)}',
              ),
              if (row.accuracyM != null)
                _DetailRow(
                  icon: Icons.radar,
                  label: 'GPS accuracy',
                  value: '±${row.accuracyM!.toStringAsFixed(0)} m',
                ),
              _DetailRow(
                icon: row.isStale
                    ? Icons.signal_wifi_off_rounded
                    : Icons.sensors_rounded,
                label: 'Signal',
                value: row.freshnessLabel,
              ),
              if (row.recordedAt != null)
                _DetailRow(
                  icon: Icons.access_time_rounded,
                  label: 'Last ping',
                  value: df.format(row.recordedAt!.toLocal()),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _mapController.move(LatLng(row.lat, row.lng), 17);
                },
                icon: const Icon(Icons.center_focus_strong),
                label: const Text('Center on rider'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
