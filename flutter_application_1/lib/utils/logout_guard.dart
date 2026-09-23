import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/notification_repository.dart';
import '../services/rental_repository.dart';

/// Confirms logout. Warns (and can alert admins) if a rental is still open.
Future<void> confirmAndSignOut(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  var hasOpenRental = false;
  String? bikeHint;

  try {
    final rental = await RentalRepository().fetchMyActiveRental();
    if (rental != null && (rental.isActive || rental.isPending)) {
      hasOpenRental = true;
      bikeHint = rental.isPending ? 'pending request' : 'active rental';
    }
  } catch (_) {}

  if (!context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        hasOpenRental ? Icons.warning_amber_rounded : Icons.logout_rounded,
        color: cs.error,
        size: 28,
      ),
      title: Text(hasOpenRental ? 'Active rental — log out?' : 'Log out?'),
      content: Text(
        hasOpenRental
            ? 'You still have a $bikeHint. Logging out, closing the app, or going offline now can be treated as suspicious activity. Admins may be notified and can review your ID. Return the bike first if you can.'
            : 'You will be returned to the login screen.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cs.error,
            foregroundColor: cs.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(hasOpenRental ? 'Log out anyway' : 'Log out'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  if (hasOpenRental) {
    try {
      await NotificationRepository().notifyAdmins(
        type: 'rider_logout_active',
        title: 'Rider logged out during a rental',
        body:
            'A rider logged out while a rental was still $bikeHint. This may be suspicious — check the map and their ID.',
      );
    } catch (_) {}
  }

  await AuthService.signOut();
}
