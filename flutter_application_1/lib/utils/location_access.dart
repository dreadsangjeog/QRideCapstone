import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

enum LocationAccessResult {
  granted,
  denied,
  awaitingPhone,
}

/// GPS on plus **while using the app**.
///
/// We do **not** require “Allow all the time.” During an active rental, the
/// “Rental in progress” foreground service keeps sharing with the screen
/// locked or another app open (still treated as using the app).
Future<LocationAccessResult> ensureLocationAccessForRental(
  BuildContext context,
) async {
  final serviceOn = await Geolocator.isLocationServiceEnabled();
  if (!serviceOn) {
    if (!context.mounted) return LocationAccessResult.denied;
    await _gpsOffDialog(context);
    return LocationAccessResult.awaitingPhone;
  }

  if (await _hasRentalLocation()) {
    return LocationAccessResult.granted;
  }

  // Request only while-in-use — never escalate to “all the time.”
  final status = await Permission.locationWhenInUse.request();
  if (await _hasRentalLocation() || status.isGranted) {
    return LocationAccessResult.granted;
  }

  if (status.isPermanentlyDenied) {
    if (context.mounted) await _openAppLocationSettings(context);
    return LocationAccessResult.awaitingPhone;
  }

  return LocationAccessResult.denied;
}

Future<bool> hasLocationAccessForRental() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  return _hasRentalLocation();
}

Future<bool> _hasRentalLocation() async {
  if (await Permission.locationWhenInUse.isGranted) return true;
  if (await Permission.locationAlways.isGranted) return true;
  if (await Permission.location.isGranted) return true;
  final geo = await Geolocator.checkPermission();
  return geo == LocationPermission.always ||
      geo == LocationPermission.whileInUse;
}

Future<void> _gpsOffDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(
          Icons.location_off_outlined,
          size: 32,
          color: t.colorScheme.error,
        ),
        title: const Text('GPS is off'),
        content: const Text(
          'Turn on Location so staff can see the bike during your ride.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            child: const Text('Turn on GPS'),
          ),
        ],
      );
    },
  );
}

Future<void> _openAppLocationSettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.my_location_rounded),
      title: const Text('Allow location'),
      content: const Text(
        'QRide needs location while you use the app so staff can see the bike. '
        'On the next screen, choose “While using the app.” The scanner stays open.',
      ),
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
    ),
  );
}
