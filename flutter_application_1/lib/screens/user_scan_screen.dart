import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/bike.dart';
import '../services/admin_repository.dart';
import '../services/auth_service.dart';
import '../services/kyc_repository.dart';
import '../services/rental_repository.dart';
import '../utils/location_access.dart';
import '../utils/network_errors.dart';
import '../widgets/bike_photo.dart';
import '../widgets/qride_brand.dart';
import '../widgets/user_portal_chrome.dart';

part 'user_scan_helpers.dart';
part 'user_scan_widgets.dart';

class UserScanScreen extends StatefulWidget {
  const UserScanScreen({super.key});

  @override
  State<UserScanScreen> createState() => _UserScanScreenState();
}

class _UserScanScreenState extends State<UserScanScreen>
    with WidgetsBindingObserver {
  final _adminRepo = AdminRepository();
  final _rentalRepo = RentalRepository();

  MobileScannerController? _scannerController;
  bool _scannerVisible = false;
  bool _openingCamera = true;
  bool _busy = false;
  bool _processingFrame = false;
  bool _waitingLocationReturn = false;
  Bike? _pendingBike;
  String? _locationHoldMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestCameraAndOpenScanner();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingLocationReturn) {
      unawaited(_resumeAfterLocationSettings());
    }
  }

  MobileScannerController _ensureController() {
    return _scannerController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  void _leaveScan() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      _closeScanner();
    }
  }

  Future<void> _requestCameraAndOpenScanner() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() => _openingCamera = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Camera scanning is for Android/iOS. Use “Enter bike code manually” on web.',
          ),
        ),
      );
      return;
    }

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;

    if (!status.isGranted) {
      if (mounted) setState(() => _openingCamera = false);
      if (status.isPermanentlyDenied) {
        await showDialog<void>(
          context: context,
          builder: (ctx) {
            final t = Theme.of(ctx);
            return AlertDialog(
              icon: Icon(
                Icons.photo_camera_outlined,
                size: 32,
                color: t.colorScheme.primary,
              ),
              title: const Text('Camera access'),
              content: const Text(
                'QRide needs the camera to scan bike codes. You can enable it in system settings.',
              ),
              actionsAlignment: MainAxisAlignment.end,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    openAppSettings();
                  },
                  child: const Text('Open settings'),
                ),
              ],
            );
          },
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to scan QR codes.'),
          ),
        );
      }
      return;
    }

    await _openScannerAfterLocation();
  }

  Future<void> _openScannerAfterLocation() async {
    final result = await ensureLocationAccessForRental(context);
    if (!mounted) return;
    if (result == LocationAccessResult.granted) {
      _waitingLocationReturn = false;
      _locationHoldMessage = null;
      setState(() {
        _ensureController();
        _scannerVisible = true;
        _openingCamera = false;
        _processingFrame = false;
      });
      return;
    }
    if (result == LocationAccessResult.awaitingPhone) {
      _waitingLocationReturn = true;
      setState(() {
        _openingCamera = false;
        _locationHoldMessage =
            'Stay on this screen. Turn on location, then return here. The scanner stays open.';
      });
      return;
    }
    setState(() {
      _openingCamera = false;
      _locationHoldMessage =
          'Allow location while using QRide so you can scan a bike. You will stay on this screen.';
    });
  }

  Future<void> _resumeAfterLocationSettings() async {
    if (await hasLocationAccessForRental()) {
      _waitingLocationReturn = false;
      _locationHoldMessage = null;
      if (!mounted) return;
      final pending = _pendingBike;
      if (!_scannerVisible) {
        setState(() {
          _ensureController();
          _scannerVisible = true;
          _openingCamera = false;
          _processingFrame = false;
        });
      }
      if (pending != null) {
        _pendingBike = null;
        await _startRentalIfAvailable(pending);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _locationHoldMessage =
          'Location is still off. Allow it for QRide, then return here.';
    });
  }

  void _closeScanner() {
    _scannerController?.stop();
    setState(() {
      _scannerVisible = false;
      _openingCamera = false;
      _processingFrame = false;
    });
  }

  Future<void> _restartScannerIfNeeded() async {
    _processingFrame = false;
    final c = _scannerController;
    if (_scannerVisible && c != null) {
      await c.start();
    }
  }

  Future<void> _handleRawScan(String raw) async {
    final code = normalizeBikeCodeFromScan(raw);
    if (code.isEmpty) {
      await _restartScannerIfNeeded();
      return;
    }

    if (!AuthService.isSignedIn) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to start a rental.')),
      );
      await _restartScannerIfNeeded();
      return;
    }

    setState(() => _busy = true);
    try {
      if (!await hasNetworkConnection()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kOfflineMessage)),
        );
        await _restartScannerIfNeeded();
        return;
      }
      final bike = await _adminRepo.fetchBikeByCode(code);
      if (!mounted) return;
      if (bike == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No bike found for code “$code”.')),
        );
        await _restartScannerIfNeeded();
        return;
      }
      await _startRentalIfAvailable(bike);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyNetworkError(e))),
      );
      await _restartScannerIfNeeded();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRentalIfAvailable(Bike bike) async {
    if (bike.status != 'available') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('This bike is not available (status: ${bike.status}).'),
        ),
      );
      await _restartScannerIfNeeded();
      return;
    }

    final kyc = await KycRepository().fetchMine();
    if (!kyc.isVerified) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kyc.isPending
                ? 'Your ID is still being checked. You can rent after you are verified.'
                : 'Verify your ID and live selfie before renting a bike.',
          ),
        ),
      );
      await _restartScannerIfNeeded();
      return;
    }

    // 1. Location service + app permission required (scan and manual code).
    if (!mounted) return;
    final locationOk = await ensureLocationAccessForRental(context);
    if (locationOk == LocationAccessResult.awaitingPhone) {
      _pendingBike = bike;
      _waitingLocationReturn = true;
      if (mounted) {
        setState(() {
          _locationHoldMessage =
              'Stay on this screen. Allow location, then return here. Your bike stays selected.';
        });
      }
      return;
    }
    if (locationOk != LocationAccessResult.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow location while using QRide to send a rental request.',
            ),
          ),
        );
      }
      await _restartScannerIfNeeded();
      return;
    }

    // 2. Show duration picker + cost summary.
    final planned = await _showDurationPicker(bike);
    if (planned == null || !mounted) {
      await _restartScannerIfNeeded();
      return;
    }

    // Re-check in case the rider revoked permission while picking duration.
    if (!await hasLocationAccessForRental()) {
      if (!mounted) return;
      final stillOk = await ensureLocationAccessForRental(context);
      if (stillOk == LocationAccessResult.awaitingPhone) {
        _pendingBike = bike;
        _waitingLocationReturn = true;
        return;
      }
      if (stillOk != LocationAccessResult.granted) {
        await _restartScannerIfNeeded();
        return;
      }
    }

    // 3. Submit request.
    try {
      if (!await hasNetworkConnection()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kOfflineMessage)),
        );
        await _restartScannerIfNeeded();
        return;
      }
      await _rentalRepo.requestRental(
        bikeId: bike.id,
        plannedMinutes: planned,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        _closeScanner();
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Request submitted! Waiting for admin approval.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final friendly = msg.contains('kyc_not_verified')
          ? 'Verify your ID and live selfie before renting a bike.'
          : msg.contains('already_has_active_rental')
              ? 'You already have an active or pending rental.'
              : msg.contains('bike_not_available')
                  ? 'This bike is no longer available.'
                  : friendlyNetworkError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
      await _restartScannerIfNeeded();
    }
  }

  /// Shows a bottom sheet for the rider to choose rental duration.
  /// Returns the chosen number of minutes, or null if cancelled.
  Future<int?> _showDurationPicker(Bike bike) async {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DurationPickerSheet(bike: bike),
    );
  }

  Future<void> _manualCodeEntry() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(
            Icons.pin_outlined,
            color: t.colorScheme.primary,
          ),
          title: const Text('Enter bike code'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Code on the bike',
              hintText: 'e.g. BIKE-01',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (code == null || code.isEmpty) return;
    await _handleRawScan(code);
  }

  static const double _kScanFrameCornerRadius = 20;

  Widget _buildScannerView(MobileScannerController controller) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scanRect = scanWindowRectForLayout(size);
        final bottomInset = MediaQuery.paddingOf(context).bottom;

        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              scanWindow: scanRect,
              tapToFocus: true,
              fit: BoxFit.cover,
              onDetect: (capture) {
                if (_processingFrame || _busy) return;
                final codes = capture.barcodes;
                if (codes.isEmpty) return;
                final raw = codes.first.rawValue;
                if (raw == null || raw.isEmpty) return;
                _processingFrame = true;
                controller.stop();
                _handleRawScan(raw);
              },
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xE61C1B1F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_off_outlined,
                              size: 40,
                              color: accent,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Couldn't start the camera",
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$error',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                              ),
                              onPressed: _busy ? null : _manualCodeEntry,
                              icon: const Icon(Icons.keyboard_rounded),
                              label: const Text('Enter code manually'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            CustomPaint(
              painter: ScanFrameOverlayPainter(
                frame: scanRect,
                cornerRadius: _kScanFrameCornerRadius,
              ),
              size: size,
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.close_rounded,
                      onPressed: _busy ? null : _leaveScan,
                      tooltip: 'Close',
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: MediaQuery.paddingOf(context).top + 52,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x4D000000),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 24,
                          spreadRadius: 0,
                          offset: Offset(0, 8),
                          color: Color(0x40000000),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            color: accent.withValues(alpha: 0.95),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Align the QR code in the frame',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_busy)
              ColoredBox(
                color: const Color(0x99000000),
                child: Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: accent,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomInset + 20,
              child: ValueListenableBuilder<MobileScannerState>(
                valueListenable: controller,
                builder: (context, state, _) {
                  final torch = state.torchState;
                  final torchAvailable = torch != TorchState.unavailable;
                  final isOn = torch == TorchState.on;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (torchAvailable)
                        _TorchFab(
                          isOn: isOn,
                          busy: _busy,
                          onPressed: () => controller.toggleTorch(),
                        ),
                      if (torchAvailable) const SizedBox(height: 14),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'QR not working? Type the bike code.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.86),
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF111827),
                                    minimumSize: const Size.fromHeight(46),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _busy ? null : _manualCodeEntry,
                                  icon: const Icon(Icons.keyboard_rounded),
                                  label: const Text('Enter code'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_scannerVisible && _scannerController != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildScannerView(_scannerController!),
      );
    }

    if (_openingCamera) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final cs = theme.colorScheme;

    return UserPortalScaffold(
      title: 'Scan bike',
      showBell: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          PolishedSectionCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              child: Column(
                children: [
                  const QrideBikeMark(size: 84),
                  const SizedBox(height: 16),
                  Text(
                    _waitingLocationReturn
                        ? 'Stay on this screen'
                        : (_locationHoldMessage != null
                            ? 'Location is required'
                            : 'Camera needs access'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _locationHoldMessage ??
                        'Allow the camera to scan a bike QR, or type the code printed on the bike.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: (kIsWeb || _busy)
                ? null
                : (_waitingLocationReturn
                    ? _resumeAfterLocationSettings
                    : _requestCameraAndOpenScanner),
            icon: Icon(
              _waitingLocationReturn
                  ? Icons.my_location_rounded
                  : Icons.photo_camera_rounded,
            ),
            label: Text(
              kIsWeb
                  ? 'Camera (mobile only)'
                  : (_waitingLocationReturn
                      ? 'I allowed location'
                      : 'Try camera again'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _manualCodeEntry,
            icon: const Icon(Icons.keyboard_rounded),
            label: const Text('Enter code manually'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
