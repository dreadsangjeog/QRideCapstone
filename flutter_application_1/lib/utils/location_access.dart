import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Returns true only when location services are on and the app has
/// location permission (while-in-use or always). Shows dialogs otherwise.
Future<bool> ensureLocationAccessForRental(BuildContext context) async {
  final serviceOn = await Geolocator.isLocationServiceEnabled();
  if (!serviceOn) {
    if (!context.mounted) return false;
    await showDialog<void>(
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
            'QRide needs your GPS to track the ride and show your location to '
            'the admin. Please enable Location Services, then try again.',
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
    return false;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always) {
    return true;
  }

  if (!context.mounted) return false;

  final permanentlyDenied =
      permission == LocationPermission.deniedForever;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx);
      return AlertDialog(
        icon: Icon(
          Icons.location_disabled_outlined,
          size: 32,
          color: t.colorScheme.error,
        ),
        title: const Text('Location permission required'),
        content: Text(
          permanentlyDenied
              ? 'QRide cannot rent a bike without location access. '
                  'Enable location permission for QRide in your device settings, '
                  'then try again.'
              : 'QRide needs location access to track your ride and show your '
                  'position to the admin. Please allow location permission to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (permanentlyDenied)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('Open settings'),
            )
          else
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await Geolocator.requestPermission();
              },
              child: const Text('Allow'),
            ),
        ],
      );
    },
  );
  return false;
}

/// Silent check used right before submitting a rental request.
Future<bool> hasLocationAccessForRental() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  final permission = await Geolocator.checkPermission();
  return permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;
}
