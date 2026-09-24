import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/device_compass.dart';
import '../services/location_tracking_service.dart';
import '../services/rental_repository.dart';
import '../services/ride_location_controller.dart';
import '../theme/brand.dart';
import '../widgets/heading_map_pin.dart';
import '../widgets/qride_map_tiles.dart';
import '../widgets/user_portal_chrome.dart';

/// Full-screen rider map. Local GPS + compass only — does not write
/// rental location (that stays on the Active rental tracker).
class UserHomeMapScreen extends StatefulWidget {
  const UserHomeMapScreen({super.key});

  @override
  State<UserHomeMapScreen> createState() => _UserHomeMapScreenState();
}

class _UserHomeMapScreenState extends State<UserHomeMapScreen> {
  final _map = MapController();
  final _rentalRepo = RentalRepository();
  final _pose = SmoothLatLng(const LatLng(14.5995, 120.9842));

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassReading>? _compassSub;
  Timer? _tick;
  Timer? _rentalPoll;

  Position? _position;
  bool _follow = true;
  bool _mapReady = false;
  bool _hasActiveRide = false;
  bool _hasPendingRide = false;
  String? _locationHint;

  @override
  void initState() {
    super.initState();
    _startLocalLocation();
    _startCompass();
    _checkRental();
    _rentalPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_checkRental());
    });
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_pose.tick()) return;
      if (!mounted) return;
      setState(() {});
      if (_follow && _mapReady) {
        try {
          _map.move(_pose.current, _map.camera.zoom);
        } catch (_) {}
      }
    });
  }

  Future<void> _checkRental() async {
    try {
      final rental = await _rentalRepo.fetchMyActiveRental();
      final active = rental != null && rental.isActive;
      final pending = rental != null && rental.isPending;
      if (!mounted) return;
      if (active == _hasActiveRide && pending == _hasPendingRide) return;
      setState(() {
        _hasActiveRide = active;
        _hasPendingRide = pending;
      });
    } catch (_) {}
  }

  Future<void> _startLocalLocation() async {
    try {
      final on = await Geolocator.isLocationServiceEnabled();
      if (!on) {
        if (mounted)
          setState(() => _locationHint = 'Turn on GPS to see yourself');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          setState(
            () => _locationHint = 'Allow location to show you on the map',
          );
        }
        return;
      }
      if (mounted) setState(() => _locationHint = null);

      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _applyPosition(first);

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen(_applyPosition);
    } catch (_) {
      if (mounted) setState(() => _locationHint = 'Could not read GPS');
    }
  }

  void _startCompass() {
    final stream = DeviceCompass.events;
    if (stream == null) return;
    _compassSub = stream.listen((event) {
      final h = event.heading;
      if (h == null || h.isNaN) return;
      var deg = h % 360;
      if (deg < 0) deg += 360;
      _pose.setTarget(_pose.target, deg);
    });
  }

  void _applyPosition(Position pos) {
    _position = pos;
    final gpsHeading = pos.heading >= 0 && pos.heading <= 360
        ? pos.heading
        : null;
    _pose.setTarget(LatLng(pos.latitude, pos.longitude), gpsHeading);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _tick?.cancel();
    _rentalPoll?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _pose.current;
    final heading = _pose.heading;
    final pos = _position;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: shown,
        initialZoom: 16,
        onMapReady: () {
          _mapReady = true;
          if (_follow) _map.move(shown, 16);
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        qrideStreetTiles(),
        if (pos != null &&
            pos.accuracy.isFinite &&
            pos.accuracy > 0 &&
            pos.accuracy < 80)
          CircleLayer(
            circles: [
              CircleMarker(
                point: shown,
                radius: pos.accuracy,
                useRadiusInMeter: true,
                color: const Color(0x331A73E8),
                borderColor: const Color(0x661A73E8),
                borderStrokeWidth: 1,
              ),
            ],
          ),
        if (pos != null)
          MarkerLayer(
            markers: [
              Marker(
                point: shown,
                width: _hasActiveRide ? 28 : 56,
                height: _hasActiveRide ? 28 : 56,
                alignment: Alignment.center,
                child: _hasActiveRide
                    ? HeadingChevron(headingDeg: heading, size: 20)
                    : MapsHeadingPuck(headingDeg: heading),
              ),
            ],
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 108),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasActiveRide || _hasPendingRide)
                  _RideStatusChip(
                    riding: _hasActiveRide,
                    tracking: RideLocationScope.maybeOf(context)?.tracking,
                    onTap: () => RiderNavScope.maybeOf(context)?.openPage(1),
                  ),
                if ((_hasActiveRide || _hasPendingRide) &&
                    _locationHint != null)
                  const SizedBox(height: 8),
                if (_locationHint != null)
                  Material(
                    color: Colors.white.withValues(alpha: 0.94),
                    elevation: 4,
                    shadowColor: Colors.black12,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        _locationHint!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: 118,
          child: GlassCircleButton(
            tooltip: 'My location',
            icon: Icons.my_location_rounded,
            foreground: _follow ? QrideBrand.accent : const Color(0xFF9CA3AF),
            onTap: () {
              setState(() => _follow = true);
              if (pos != null) {
                try {
                  _map.move(_pose.current, _map.camera.zoom);
                } catch (_) {
                  _map.move(_pose.current, 16);
                }
              } else {
                unawaited(_startLocalLocation());
              }
            },
          ),
        ),
      ],
    );
  }
}

class _RideStatusChip extends StatelessWidget {
  const _RideStatusChip({
    required this.riding,
    required this.onTap,
    this.tracking,
  });

  final bool riding;
  final VoidCallback onTap;
  final LocationTrackingService? tracking;

  @override
  Widget build(BuildContext context) {
    final tracking = this.tracking;
    if (!riding || tracking == null) {
      return _chip(
        color: riding ? QrideBrand.accent : const Color(0xFFD97706),
        label: riding ? 'Ride in progress' : 'Waiting for approval',
      );
    }
    return ValueListenableBuilder<String?>(
      valueListenable: tracking.lastError,
      builder: (context, err, _) {
        return ValueListenableBuilder<DateTime?>(
          valueListenable: tracking.lastWriteAt,
          builder: (context, writeAt, _) {
            if (err != null) {
              return _chip(
                color: const Color(0xFFDC2626),
                label: 'Location not reaching admin',
              );
            }
            if (writeAt == null) {
              return _chip(
                color: QrideBrand.accent,
                label: 'Starting location share…',
              );
            }
            return _chip(
              color: const Color(0xFF16A34A),
              label: 'Sharing location with admin',
            );
          },
        );
      },
    );
  }

  Widget _chip({required Color color, required String label}) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
