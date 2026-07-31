import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:geolocator/geolocator.dart';

import '../models/bike.dart';
import '../services/admin_repository.dart';
import '../services/auth_service.dart';
import '../services/rental_repository.dart';
import '../widgets/user_portal_chrome.dart';

part 'user_scan_helpers.dart';
part 'user_scan_widgets.dart';

class UserScanScreen extends StatefulWidget {
  const UserScanScreen({super.key});

  @override
  State<UserScanScreen> createState() => _UserScanScreenState();
}

class _UserScanScreenState extends State<UserScanScreen> {
  final _adminRepo = AdminRepository();
  final _rentalRepo = RentalRepository();

  MobileScannerController? _scannerController;
  bool _scannerVisible = false;
  bool _busy = false;
  bool _processingFrame = false;

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  MobileScannerController _ensureController() {
    return _scannerController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  Future<void> _requestCameraAndOpenScanner() async {
    if (kIsWeb) {
      if (!mounted) return;
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

    setState(() {
      _ensureController();
      _scannerVisible = true;
      _processingFrame = false;
    });
  }

  void _closeScanner() {
    _scannerController?.stop();
    setState(() {
      _scannerVisible = false;
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
        SnackBar(content: Text(e.toString())),
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

    // 1. GPS must be enabled before the rider can request a rental.
    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!gpsEnabled) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final t = Theme.of(ctx);
          return AlertDialog(
            icon: Icon(Icons.location_off_outlined,
                size: 32, color: t.colorScheme.error),
            title: const Text('GPS is off'),
            content: const Text(
              'QRide needs your GPS to track the ride and show your location to the admin. '
              'Please enable Location Services in your device settings, then try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Geolocator.openLocationSettings();
                },
                child: const Text('Open settings'),
              ),
            ],
          );
        },
      );
      await _restartScannerIfNeeded();
      return;
    }

    // 2. Show duration picker + cost summary.
    final planned = await _showDurationPicker(bike);
    if (planned == null || !mounted) {
      await _restartScannerIfNeeded();
      return;
    }

    // 3. Submit request.
    try {
      await _rentalRepo.requestRental(
        bikeId: bike.id,
        plannedMinutes: planned,
      );
      if (!mounted) return;
      _closeScanner();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request submitted! Waiting for admin approval.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final friendly = msg.contains('already_has_active_rental')
          ? 'You already have an active or pending rental.'
          : msg.contains('bike_not_available')
              ? 'This bike is no longer available.'
              : msg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
      await _restartScannerIfNeeded();
    }
  }

  /// Shows a bottom sheet for the rider to choose rental duration.
  /// Returns the chosen number of minutes, or null if cancelled.
  Future<int?> _showDurationPicker(Bike bike) async {
    final bikeLabel = bike.label?.trim().isNotEmpty == true
        ? '${bike.label} (${bike.code})'
        : 'Bike ${bike.code}';

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DurationPickerSheet(bikeLabel: bikeLabel),
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
                      onPressed: _busy ? null : _closeScanner,
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

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x66000000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 32,
                          offset: Offset(0, 12),
                          color: Color(0x59000000),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (torchAvailable)
                            _TorchFab(
                              isOn: isOn,
                              busy: _busy,
                              onPressed: () => controller.toggleTorch(),
                            ),
                          if (torchAvailable) const SizedBox(height: 14),
                          Text(
                            "Tap the preview to focus. We'll start your rental when the code matches an available bike.",
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
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

    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Scan bike'),
        backgroundColor: Color.lerp(cs.surface, cs.primaryContainer, 0.08),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: UserPortalBackdrop(colorScheme: cs)),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surface.withValues(alpha: 0.72),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.12),
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 28,
                        spreadRadius: 0,
                        offset: const Offset(0, 10),
                        color: cs.primary.withValues(alpha: 0.08),
                      ),
                    ],
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.qr_code_2_rounded,
                      size: 34,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Start a rental',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan the QR on the bike with your camera, or type the code if you prefer.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              Material(
                color: cs.surface.withValues(alpha: 0.82),
                elevation: 0,
                shadowColor: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                    child: Row(
                      children: [
                        Icon(Icons.tips_and_updates_outlined, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Allow camera access when prompted so we can read the code.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (kIsWeb || _busy) ? null : _requestCameraAndOpenScanner,
                icon: const Icon(Icons.photo_camera_rounded),
                label: Text(
                  kIsWeb ? 'Camera (mobile only)' : 'Open camera',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: cs.surface.withValues(alpha: 0.65),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : _manualCodeEntry,
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('Enter code manually'),
              ),
              if (_busy) ...[
                const SizedBox(height: 28),
                Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
