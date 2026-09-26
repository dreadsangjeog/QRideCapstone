import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

enum LocationAccessResult {
  granted,
  denied,
  awaitingPhone,
}

/// GPS on plus location while using the app (or all the time).
/// Android’s system sheet always includes “While using the app” — we cannot
/// hide that. A rental still shares in the background via a foreground service.
Future<LocationAccessResult> ensureLocationAccessForRental(
  BuildContext context, {
  bool offerBattery = true,
}) async {
  final serviceOn = await Geolocator.isLocationServiceEnabled();
  if (!serviceOn) {
    if (!context.mounted) return LocationAccessResult.denied;
    await _gpsOffDialog(context);
    return LocationAccessResult.awaitingPhone;
  }

  if (await _hasRentalLocation()) {
    if (offerBattery && context.mounted) {
      await _offerUnrestrictedBattery(context);
    }
    return LocationAccessResult.granted;
  }

  final status = await Permission.location.request();
  if (await _hasRentalLocation() || status.isGranted) {
    if (offerBattery && context.mounted) {
      await _offerUnrestrictedBattery(context);
    }
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

Future<bool> hasAlwaysLocation() => _hasRentalLocation();

Future<void> offerBackgroundLocation(BuildContext context) async {}

Future<bool> _hasRentalLocation() async {
  if (await Permission.locationAlways.isGranted) return true;
  if (await Permission.locationWhenInUse.isGranted) return true;
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
        'On the next screen, allow location. The scanner stays open.',
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

Future<void> _offerUnrestrictedBattery(BuildContext context) async {
  final status = await Permission.ignoreBatteryOptimizations.status;
  if (status.isGranted) return;
  if (!context.mounted) return;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.battery_charging_full_rounded),
      title: const Text('Keep sharing during the ride'),
      content: const Text(
        'If you allow this, QRide can keep sharing the bike while the screen '
        'is off or you leave the app. A “Rental in progress” notice stays on '
        'until the ride ends.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (go == true) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}
