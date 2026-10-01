import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/notification_repository.dart';
import '../services/rental_repository.dart';
import '../services/supabase_client.dart';

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
            ? 'You still have a $bikeHint. Logging out now notifies staff, and they can review your ID and last location. Leaving the app or locking the phone does not log you out, and location sharing continues. Return the bike and wait until staff end the ride if you can.'
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
    final username = await _signedInUsername();
    final who = username ?? 'A rider';
    try {
      await NotificationRepository().notifyAdmins(
        type: 'rider_logout_active',
        title: username == null
            ? 'Rider logged out during a rental'
            : '$username logged out during a rental',
        body:
            '$who logged out while a rental was still $bikeHint. This may be suspicious — check the map and their ID.',
        data: username == null ? null : {'username': username},
      );
    } catch (_) {}
  }

  await AuthService.signOut();
  if (!context.mounted) return;
  // Account settings (and the KYC wizard) sit on top of the signed-in app.
  // Signing out swaps the root to login, but that route stays until it is popped.
  Navigator.of(context).popUntil((route) => route.isFirst);
}

Future<String?> _signedInUsername() async {
  final uid = SupabaseClientProvider.client.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    final row = await SupabaseClientProvider.client
        .from('profiles')
        .select('username')
        .eq('id', uid)
        .maybeSingle();
    final name = (row?['username'] ?? '').toString().trim();
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}
