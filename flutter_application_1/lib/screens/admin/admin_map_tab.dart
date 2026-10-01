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
import '../../widgets/qride_glass.dart';
import '../../widgets/qride_map_tiles.dart';
import 'admin_layout.dart';

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
  /// Last stable pin signal per rental — used for yellow/red hysteresis.
  final Map<String, _RiderSignal> _signalByRental = {};

  /// When the admin map last accepted a newer GPS sample for each rental.
  /// Color follows this clock so an older fetch cannot turn a live pin yellow.
  final Map<String, DateTime> _observedAtByRental = {};
  final Map<String, DateTime> _recordedAtByRental = {};
  int _loadGen = 0;
  bool _loadingRiders = false;
  DateTime? _lastRefresh;
  Timer? _refreshTimer;
  Timer? _smoothTimer;
  Timer? _staleTimer;
  RealtimeChannel? _locationChannel;
  final Set<String> _offlineNotified = {};
  final _notifRepo = NotificationRepository();

  bool _mapReady = false;
  bool _panelOpen = true;
  final _panelScroll = ScrollController();

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
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadRiders(silent: true);
    });
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _refreshStableSignals();
      setState(() {});
      _notifyNewlyOffline();
    });
  }

  _RiderSignal _signalFor(_MarkerRow r) {
    return r.signalWithHysteresis(
      _signalByRental[r.rentalId],
      anchor: _observedAtByRental[r.rentalId],
    );
  }

  void _refreshStableSignals() {
    for (final r in _riders) {
      _signalByRental[r.rentalId] = r.signalWithHysteresis(
        _signalByRental[r.rentalId],
      );
    }
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
    _panelScroll.dispose();
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

    _locationSub =
        Geolocator.getPositionStream(
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
    final gen = ++_loadGen;
    if (!silent) setState(() => _loadingRiders = true);
    try {
      final rows = await widget.repo.fetchActiveRentalLastLocationsJoined();
      final parsed = rows
          .map(_MarkerRow.fromJoined)
          .whereType<_MarkerRow>()
          .toList();
      if (!mounted || gen != _loadGen) return;
      final merged = _mergeFresher(parsed);
      final ids = merged.map((r) => r.rentalId).toSet();
      _poses.removeWhere((id, _) => !ids.contains(id));
      _offlineNotified.removeWhere((id) => !ids.contains(id));
      _signalByRental.removeWhere((id, _) => !ids.contains(id));
      _observedAtByRental.removeWhere((id, _) => !ids.contains(id));
      _recordedAtByRental.removeWhere((id, _) => !ids.contains(id));
      setState(() {
        _riders = merged;
        _loadingRiders = false;
        _lastRefresh = DateTime.now();
      });
      _refreshStableSignals();
      _notifyNewlyOffline();
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() => _loadingRiders = false);
    }
  }

  /// Drops out-of-order snapshots. A newer `recorded_at` moves the pin and
  /// resets the live/yellow clock; an older one is ignored.
  List<_MarkerRow> _mergeFresher(List<_MarkerRow> parsed) {
    final byId = <String, _MarkerRow>{};
    for (final row in parsed) {
      final existing = byId[row.rentalId];
      if (existing == null) {
        byId[row.rentalId] = row;
        continue;
      }
      final a = existing.recordedAt;
      final b = row.recordedAt;
      if (a == null || (b != null && b.isAfter(a))) byId[row.rentalId] = row;
    }

    final previousById = {for (final r in _riders) r.rentalId: r};
    final now = DateTime.now().toUtc();
    final merged = <_MarkerRow>[];
    for (final incoming in byId.values) {
      final prev = previousById[incoming.rentalId];
      final prevAt = _recordedAtByRental[incoming.rentalId] ?? prev?.recordedAt;
      final nextAt = incoming.recordedAt;
      final isNewer =
          nextAt != null && (prevAt == null || nextAt.isAfter(prevAt));
      final isOlder =
          nextAt != null && prevAt != null && nextAt.isBefore(prevAt);
      final row = isOlder && prev != null ? prev : incoming;
      merged.add(row);
      if (isNewer && nextAt != null) {
        _recordedAtByRental[row.rentalId] = nextAt.toUtc();
        // First sample keeps its real age. Later samples count from arrival
        // so a steady 3s upload stays red instead of bouncing through yellow.
        if (prevAt == null) {
          final age = row.age ?? Duration.zero;
          _observedAtByRental[row.rentalId] = now.subtract(age);
        } else {
          _observedAtByRental[row.rentalId] = now;
        }
      } else if (!_observedAtByRental.containsKey(row.rentalId)) {
        final age = row.age ?? Duration.zero;
        _observedAtByRental[row.rentalId] = now.subtract(age);
        if (row.recordedAt != null) {
          _recordedAtByRental[row.rentalId] = row.recordedAt!.toUtc();
        }
      }
      if (isOlder) continue;
      final pose = _poses.putIfAbsent(
        row.rentalId,
        () => SmoothLatLng(LatLng(row.lat, row.lng)),
      );
      pose.setTarget(LatLng(row.lat, row.lng), row.heading);
    }
    return merged;
  }

  void _notifyNewlyOffline() {
    for (final r in _riders) {
      if (_signalFor(r) != _RiderSignal.lost) {
        _offlineNotified.remove(r.rentalId);
        continue;
      }
      if (!_offlineNotified.add(r.rentalId)) continue;
      final body =
          '${r.username} on ${r.bikeLabel} has not sent a GPS update for ${_MarkerRow._formatAge(r.age ?? Duration.zero)}. Last point is still on the map.';
      unawaited(
        _notifRepo.notifyAdmins(
          type: 'rider_offline',
          title: 'Rider location not updating',
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
            title: 'Rider location not updating',
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

    final liveCount =
        _riders.where((r) => _signalFor(r) == _RiderSignal.live).length;
    final delayedCount =
        _riders.where((r) => _signalFor(r) == _RiderSignal.delayed).length;
    final staleCount = _riders.length - liveCount - delayedCount;

    final riderMarkers = _poses.entries.map((e) {
      _MarkerRow? row;
      for (final r in _riders) {
        if (r.rentalId == e.key) {
          row = r;
          break;
        }
      }
      final signal =
          row == null ? _RiderSignal.waiting : _signalFor(row);
      final pinColor = switch (signal) {
        _RiderSignal.live => cs.error,
        _RiderSignal.delayed => const Color(0xFFF59E0B),
        _RiderSignal.lost || _RiderSignal.waiting => cs.outline,
      };
      return Marker(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        point: e.value.current,
        child: GestureDetector(
          onTap: row == null ? null : () => _showRiderDetails(row!),
          child: Opacity(
            opacity: signal == _RiderSignal.live ? 1 : 0.7,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                HeadingChevron(
                  headingDeg: e.value.heading,
                  color: pinColor,
                  size: 20,
                ),
                if (signal == _RiderSignal.lost)
                  const Positioned(
                    right: -2,
                    top: -2,
                    child: Icon(
                      Icons.schedule_rounded,
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

    final wide = adminWide(context);
    void centerAdmin() => _mapController.move(
      LatLng(_adminPos!.latitude, _adminPos!.longitude),
      16,
    );

    final statusCard = _StatusCard(
      riderCount: _riders.length,
      liveCount: liveCount,
      delayedCount: delayedCount,
      staleCount: staleCount,
      lastRefresh: _lastRefresh,
      loading: _loadingRiders,
      hasAdminGps: _adminPos != null,
      onRefresh: () => _loadRiders(),
      onCenterAdmin: _adminPos == null ? null : centerAdmin,
    );

    final ridersButton = FloatingActionButton.extended(
      heroTag: 'admin-map-riders-fab',
      onPressed: wide
          ? () => setState(() => _panelOpen = true)
          : _showRidersList,
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
    );

    final map = Stack(
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
        if (wide)
          Positioned(
            top: 16,
            left: 16,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, minWidth: 320),
              child: statusCard,
            ),
          )
        else
          Positioned(top: 12, left: 12, right: 12, child: statusCard),
        Positioned(
          bottom: 16,
          left: wide ? 16 : 12,
          child: _Legend(errorColor: cs.error),
        ),
        if (!wide || !_panelOpen)
          Positioned(bottom: 16, right: wide ? 16 : 12, child: ridersButton),
      ],
    );

    if (!wide) return map;

    return Row(
      children: [
        Expanded(child: map),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: _panelOpen
              ? Container(
                  width: 380,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0x99101828)
                        : Colors.white.withValues(alpha: 0.42),
                    border: Border(
                      left: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.only(top: 14),
                  child: _RidersListSheet(
                    riders: _riders,
                    loading: _loadingRiders,
                    scrollController: _panelScroll,
                    onRefresh: () => _loadRiders(),
                    onClose: () => setState(() => _panelOpen = false),
                    onLocate: (rider) =>
                        _mapController.move(LatLng(rider.lat, rider.lng), 17),
                    onDetails: _showRiderDetails,
                    signalFor: _signalFor,
                  ),
                )
              : const SizedBox(width: 0, height: double.infinity),
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
            signalFor: _signalFor,
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

    final wide = adminWide(context);
    Widget content(BuildContext ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, wide ? 20 : 8, 20, 20),
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        row.bikeCode,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (wide)
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded),
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
              icon: _signalFor(row) == _RiderSignal.live
                  ? Icons.sensors_rounded
                  : Icons.schedule_rounded,
              label: 'Location share',
              value: row.freshnessLabelFor(_signalFor(row)),
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
    );

    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: content(ctx),
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: content,
    );
  }
}
