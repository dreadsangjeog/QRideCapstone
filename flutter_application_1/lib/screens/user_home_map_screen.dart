import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/rental.dart';
import '../services/device_compass.dart';
import '../services/location_tracking_service.dart';
import '../services/rental_repository.dart';
import '../services/ride_foreground_task.dart';
import '../services/ride_location_controller.dart';
import '../utils/location_access.dart';
import '../theme/brand.dart';
import '../widgets/heading_map_pin.dart';
import '../widgets/qride_map_tiles.dart';
import '../widgets/user_portal_chrome.dart';
import 'user_active_rental_screen.dart';

/// Full-screen rider map.
///
/// Outside a rental: local GPS + compass only (does not write to admin).
/// During an active rental: shows the same [LocationTrackingService] fix that
/// is upserted to admin, so rider pin and admin pin stay aligned.
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
  LocationTrackingService? _rentalTracking;

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
  bool _startingLocal = false;

  /// The next live fix is shown where it is. Easing from the placeholder,
  /// or from a point left on screen through a long lock, is the slide
  /// across the map when QRide opens.
  bool _snapNextFix = true;

  /// GPS wanders for a few seconds after the app opens, then settles.
  /// During that window a loose reading cannot walk the pin around.
  DateTime? _gpsOpenedAt;
  bool _pinLocked = false;
  LatLng? _settleHold;

  /// Local GPS stays off until this is true, so it cannot start beside the
  /// rental listener while the first ride check is still in flight.
  bool _rentalChecked = false;

  /// The location prompt is shown once, after we know there is no active ride.
  bool _askedLocation = false;

  /// During a rental, prefer the shared tracker (same coords admin receives).
  /// [isTracking] flips as soon as the ride writer starts, before the rental
  /// card poll, so the home map drops its own GPS stream immediately.
  bool get _useRentalTracker => _rentalTracking?.isTracking ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCompass();
    _checkRental();
    _rentalPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_checkRental());
    });
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_useRentalTracker && _posSub != null) {
        unawaited(_posSub?.cancel());
        _posSub = null;
      }
      final moving = _pose.tick();
      final now = DateTime.now();
      // The ride card countdown only needs a new frame each second.
      final newSecond = _hasActiveRide &&
          now.millisecondsSinceEpoch ~/ 1000 !=
              _now.millisecondsSinceEpoch ~/ 1000;
      if (!moving && !newSecond) return;
      if (!mounted) return;
      if (_hasActiveRide) _now = now;
      setState(() {});
      if (_follow && _mapReady) {
        try {
          _map.move(_pose.current, _map.camera.zoom);
        } catch (_) {}
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = RideLocationScope.maybeOf(context)?.tracking;
    if (next == _rentalTracking) return;
    _rentalTracking?.position.removeListener(_onRentalTrackingUpdate);
    _rentalTracking?.heading.removeListener(_onRentalTrackingUpdate);
    _rentalTracking = next;
    _rentalTracking?.position.addListener(_onRentalTrackingUpdate);
    _rentalTracking?.heading.addListener(_onRentalTrackingUpdate);
    _onRentalTrackingUpdate();
    unawaited(_syncLocalStreamMode());
  }

  void _onRentalTrackingUpdate() {
    if (!_useRentalTracker) return;
    if (_posSub != null) {
      unawaited(_posSub?.cancel());
      _posSub = null;
    }
    final pos = _rentalTracking?.position.value;
    if (pos == null) return;
    final hdg = _rentalTracking?.heading.value;
    if (!_showFix(
      LatLng(pos.latitude, pos.longitude),
      hdg,
      pos.timestamp,
      pos.accuracy,
    )) {
      return;
    }
    _position = pos;
    if (mounted) setState(() => _locationHint = null);
  }

  Future<void> _checkRental() async {
    var failed = false;
    try {
      final rental = await _rentalRepo.fetchMyActiveRental();
      final active = rental != null && rental.isActive;
      final pending = rental != null && rental.isPending;
      if (!mounted) return;
      final sameRide = rental?.id == _rental?.id &&
          rental?.plannedMinutes == _rental?.plannedMinutes &&
          rental?.approvedAt == _rental?.approvedAt &&
          rental?.status == _rental?.status;
      final local = _rental;
      // A poll that started before Extend time finished still has the old
      // duration. Don't put that shorter booking back on the card.
      final keepLongerPlan = rental != null &&
          local != null &&
          rental.id == local.id &&
          rental.plannedMinutes < local.plannedMinutes;
      final unchanged =
          active == _hasActiveRide && pending == _hasPendingRide && sameRide;
      if (!keepLongerPlan && !unchanged) {
        setState(() {
          _hasActiveRide = active;
          _hasPendingRide = pending;
          _rental = rental;
        });
        if (active) _onRentalTrackingUpdate();
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    if (failed) {
      if (_hasActiveRide ||
          _useRentalTracker ||
          await _rentalGpsOwnsLocation()) {
        await _posSub?.cancel();
        _posSub = null;
      }
      return;
    }
    _rentalChecked = true;
    await _syncLocalStreamMode();
  }

  /// One GPS consumer on the phone: rental tracker while riding, else local.
  Future<void> _syncLocalStreamMode() async {
    final serviceOwns = await _rentalGpsOwnsLocation();
    if (!_rentalChecked &&
        !_hasActiveRide &&
        !_useRentalTracker &&
        !serviceOwns) {
      return;
    }
    if (_hasActiveRide || _useRentalTracker || serviceOwns) {
      await _posSub?.cancel();
      _posSub = null;
      if (_useRentalTracker || _hasActiveRide) _onRentalTrackingUpdate();
      return;
    }
    if (!_askedLocation) {
      _askedLocation = true;
      await _askLocationThenStart();
      return;
    }
    await _startLocalLocation();
  }

  /// True while the rental service is the phone's location client.
  Future<bool> _rentalGpsOwnsLocation() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return RideForegroundTask.isRunning;
  }

  Future<void> _startLocalLocation() async {
    if (_hasActiveRide || _useRentalTracker || _startingLocal) return;
    if (await _rentalGpsOwnsLocation()) return;
    _startingLocal = true;
    try {
      if (!await hasLocationAccessForRental()) return;
      if (_hasActiveRide || _useRentalTracker || await _rentalGpsOwnsLocation()) {
        return;
      }
      if (_posSub != null) {
        if (mounted) setState(() => _locationHint = null);
        return;
      }
      if (mounted) setState(() => _locationHint = null);

      final first = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (_hasActiveRide || _useRentalTracker || !mounted || _posSub != null) {
        return;
      }
      if (await _rentalGpsOwnsLocation()) return;
      _applyPosition(first);

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).listen((pos) {
        if (_hasActiveRide || _useRentalTracker) return;
        _applyPosition(pos);
      });
    } catch (_) {
      if (mounted) setState(() => _locationHint = 'Could not read GPS');
    } finally {
      _startingLocal = false;
    }
  }

  void _startCompass() {
    final stream = DeviceCompass.events;
    if (stream == null) return;
    _compassSub = stream.listen((event) {
      // During rental, heading comes from the shared tracker (same as admin).
      if (_useRentalTracker) return;
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
    final history = await _rentalRepo.fetchRateHistory();
    if (!mounted) return;
    final extra = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ExtendTimeSheet(
        currentPlannedMinutes: rental.plannedMinutes,
        ratePerHour: rental.ratePerHour,
        approvedAt: rental.approvedAt,
        history: history,
      ),
    );
    if (extra == null || !mounted) return;
    setState(() => _extending = true);
    try {
      final refreshed = await _rentalRepo.extendRental(
        rentalId: rental.id,
        extraMinutes: extra,
      );
      if (!mounted) return;
      setState(() {
        _rental = refreshed;
        _hasActiveRide = refreshed.isActive;
        _extending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _extending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(extendErrorText(e))));
    }
  }

  void _applyPosition(Position pos) {
    final gpsHeading = pos.heading >= 0 && pos.heading <= 360
        ? pos.heading
        : null;
    if (!_showFix(
      LatLng(pos.latitude, pos.longitude),
      gpsHeading,
      pos.timestamp,
      pos.accuracy,
    )) {
      return;
    }
    _position = pos;
    if (mounted) setState(() {});
  }

  /// Shows [next] on the map. The first live fix after open or resume
  /// appears there immediately. While the chip is still locking, later
  /// readings have to be tight or repeat before the pin moves. After that,
  /// a shift under 5 meters stays put.
  bool _showFix(LatLng next, double? heading, DateTime at, double accuracy) {
    final age = DateTime.now().toUtc().difference(at.toUtc());
    final live = age.isNegative || age <= const Duration(seconds: 20);
    if (!live) return false;
    if (_snapNextFix) {
      if (accuracy > 80) return false;
      _pose.snapTo(next, heading);
      _snapNextFix = false;
      _gpsOpenedAt = DateTime.now();
      _pinLocked = accuracy > 0 && accuracy <= 12;
      _settleHold = null;
      if (_follow && _mapReady) {
        try {
          _map.move(next, _map.camera.zoom);
        } catch (_) {
          _map.move(next, 16);
        }
      }
      return true;
    }

    final moved = Geolocator.distanceBetween(
      _pose.target.latitude,
      _pose.target.longitude,
      next.latitude,
      next.longitude,
    );
    final warming = _gpsOpenedAt != null &&
        DateTime.now().difference(_gpsOpenedAt!) < const Duration(seconds: 20);

    if (warming && !_pinLocked) {
      if (accuracy > 0 && accuracy <= 12) {
        _pose.snapTo(next, heading);
        _pinLocked = true;
        _settleHold = null;
        return true;
      }
      _keepHeading(heading);
      return false;
    }

    if (moved < 5 || accuracy > 30) {
      _keepHeading(heading);
      return false;
    }

    if (warming) {
      final held = _settleHold;
      if (held == null ||
          Geolocator.distanceBetween(
                held.latitude,
                held.longitude,
                next.latitude,
                next.longitude,
              ) >
              12) {
        _settleHold = next;
        _keepHeading(heading);
        return false;
      }
      _settleHold = null;
      _pinLocked = true;
      _pose.snapTo(next, heading);
      return true;
    }

    _pose.setTarget(next, heading);
    return true;
  }

  void _keepHeading(double? heading) {
    if (heading == null || heading < 0 || heading > 360) return;
    _pose.setTarget(_pose.target, heading);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _snapNextFix = true;
      _pinLocked = false;
      _settleHold = null;
      _gpsOpenedAt = null;
      if (_hasActiveRide || _useRentalTracker) {
        unawaited(_posSub?.cancel());
        _posSub = null;
        _onRentalTrackingUpdate();
        return;
      }
      unawaited(_checkRental());
    }
  }

  Future<void> _askLocationThenStart({bool fromResume = false}) async {
    if (!mounted) return;
    // A second location client, opened when QRide comes back from a long
    // lock, stalls the rental GPS until both are stuck.
    if (_hasActiveRide || _useRentalTracker || await _rentalGpsOwnsLocation()) {
      await _posSub?.cancel();
      _posSub = null;
      if (_hasActiveRide || _useRentalTracker) _onRentalTrackingUpdate();
      return;
    }
    if (await hasLocationAccessForRental()) {
      _waitingLocationSettings = false;
      await _startLocalLocation();
      return;
    }
    if (fromResume && !_waitingLocationSettings) return;
    if (!mounted) return;
    final result = await ensureLocationAccessForRental(context);
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
    _rentalTracking?.position.removeListener(_onRentalTrackingUpdate);
    _rentalTracking?.heading.removeListener(_onRentalTrackingUpdate);
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
          if (_follow && !_snapNextFix) _map.move(_pose.current, 16);
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        ...qrideStreetTiles(),
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
                color: _mapSheetColor(context),
                elevation: 4,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Text(
                    _locationHint!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _mapSheetText(context),
                    ),
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

Color _mapSheetColor(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? const Color(0xFF1B2433) : Colors.white.withValues(alpha: 0.96);
}

Color _mapSheetText(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? const Color(0xFFE8EEF6) : const Color(0xFF1F2937);
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
      color: _mapSheetColor(context),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.28),
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
                onPressed: extending || overtime ? null : onExtend,
                child: Text(
                  overtime
                      ? 'Time is up. Return the bike'
                      : extending
                          ? 'Extending…'
                          : 'Extend time',
                ),
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
      color: _mapSheetColor(context),
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Waiting for staff',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFF5B942)
                    : const Color(0xFFB45309),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your $hours request is in the queue. Ride time starts after they approve.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _mapSheetText(context),
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
