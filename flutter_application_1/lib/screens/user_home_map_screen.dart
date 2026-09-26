import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/rental.dart';
import '../services/device_compass.dart';
import '../services/rental_repository.dart';
import '../utils/location_access.dart';
import '../theme/brand.dart';
import '../widgets/heading_map_pin.dart';
import '../widgets/qride_map_tiles.dart';
import '../widgets/user_portal_chrome.dart';
import 'user_active_rental_screen.dart';

/// Full-screen rider map. Local GPS + compass only — does not write
/// rental location (that stays on the Active rental tracker).
class UserHomeMapScreen extends StatefulWidget {
  const UserHomeMapScreen({super.key});

  @override
  State<UserHomeMapScreen> createState() => _UserHomeMapScreenState();
}

class _UserHomeMapScreenState extends State<UserHomeMapScreen>
    with WidgetsBindingObserver {
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
  Rental? _rental;
  DateTime _now = DateTime.now();
  bool _extending = false;
  String? _locationHint;
  bool _waitingLocationSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_askLocationThenStart());
    _startCompass();
    _checkRental();
    _rentalPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_checkRental());
    });
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_pose.tick() && !_hasActiveRide) return;
      if (!mounted) return;
      if (_hasActiveRide) _now = DateTime.now();
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
      final sameRide = rental?.id == _rental?.id &&
          rental?.plannedMinutes == _rental?.plannedMinutes &&
          rental?.approvedAt == _rental?.approvedAt &&
          rental?.status == _rental?.status;
      if (active == _hasActiveRide && pending == _hasPendingRide && sameRide) {
        return;
      }
      setState(() {
        _hasActiveRide = active;
        _hasPendingRide = pending;
        _rental = rental;
      });
    } catch (_) {}
  }

  Future<void> _startLocalLocation() async {
    try {
      if (!await hasLocationAccessForRental()) return;
      if (_posSub != null) {
        if (mounted) setState(() => _locationHint = null);
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

  Future<void> _cancelPendingFromHome(Rental rental) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel request?'),
        content: const Text(
          'Staff will no longer see this bike request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _rentalRepo.cancelPendingRental(rentalId: rental.id);
      if (!mounted) return;
      setState(() {
        _rental = null;
        _hasPendingRide = false;
      });
    } catch (_) {}
  }

  Future<void> _extendFromHome(Rental rental) async {
    final extra = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ExtendTimeSheet(
        currentPlannedMinutes: rental.plannedMinutes,
        ratePerHour: rental.ratePerHour,
      ),
    );
    if (extra == null || !mounted) return;
    setState(() => _extending = true);
    try {
      await _rentalRepo.extendRental(rentalId: rental.id, extraMinutes: extra);
      final refreshed = await _rentalRepo.fetchRentalById(rental.id);
      if (!mounted) return;
      setState(() {
        _rental = refreshed ?? rental;
        _hasActiveRide = (_rental?.isActive ?? false);
        _extending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _extending = false);
    }
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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_askLocationThenStart(fromResume: true));
    }
  }

  Future<void> _askLocationThenStart({bool fromResume = false}) async {
    if (!mounted) return;
    if (await hasLocationAccessForRental()) {
      _waitingLocationSettings = false;
      await _startLocalLocation();
      return;
    }
    if (fromResume && !_waitingLocationSettings) return;
    final result = await ensureLocationAccessForRental(
      context,
      offerBattery: false,
    );
    if (!mounted) return;
    _waitingLocationSettings = result == LocationAccessResult.awaitingPhone;
    if (result == LocationAccessResult.granted) {
      await _startLocalLocation();
      return;
    }
    setState(() {
      _locationHint = result == LocationAccessResult.awaitingPhone
          ? 'Turn on location, then return here to see yourself on the map'
          : 'Allow location to see yourself on the map';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        Positioned(
          top: MediaQuery.paddingOf(context).top + 62,
          left: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasActiveRide && _rental != null)
                _ActiveRideCard(
                  rental: _rental!,
                  now: _now,
                  extending: _extending,
                  onExtend: () => _extendFromHome(_rental!),
                )
              else if (_hasPendingRide && _rental != null)
                _PendingRideCard(
                  rental: _rental!,
                  onCancel: () => _cancelPendingFromHome(_rental!),
                ),
            ],
          ),
        ),
        if (_locationHint != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 108),
              child: Material(
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

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({
    required this.rental,
    required this.now,
    required this.extending,
    required this.onExtend,
  });

  final Rental rental;
  final DateTime now;
  final bool extending;
  final VoidCallback onExtend;

  @override
  Widget build(BuildContext context) {
    final end = rental.scheduledEndTime;
    final overtime = end != null && now.isAfter(end);
    final remaining = end == null
        ? Duration.zero
        : overtime
            ? now.difference(end)
            : end.difference(now);
    final clock = overtime
        ? '+${remaining.inMinutes}m ${remaining.inSeconds % 60}s'
        : '${remaining.inHours > 0 ? '${remaining.inHours}h ' : ''}'
            '${remaining.inMinutes % 60}m ${remaining.inSeconds % 60}s';
    final color = overtime ? const Color(0xFFDC2626) : QrideBrand.accent;

    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  overtime ? Icons.timer_off_rounded : Icons.timer_rounded,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overtime ? 'Overtime' : 'Time left',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        clock,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -0.4,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: extending ? null : onExtend,
                child: Text(extending ? 'Extending…' : 'Extend time'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRideCard extends StatelessWidget {
  const _PendingRideCard({
    required this.rental,
    required this.onCancel,
  });

  final Rental rental;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final hours = rental.plannedMinutes >= 60
        ? '${rental.plannedMinutes ~/ 60}h'
        : '${rental.plannedMinutes}m';
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Waiting for staff',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your $hours request is in the queue. Ride time starts after they approve.',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF5B6B80),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onCancel,
              child: const Text('Cancel request'),
            ),
          ],
        ),
      ),
    );
  }
}
