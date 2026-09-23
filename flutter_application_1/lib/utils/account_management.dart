import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/rental_repository.dart';
import 'network_errors.dart';

/// Confirms and permanently deletes the signed-in rider account.
Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  var hasOpenRental = false;
  String? bikeHint;

  try {
    final rental = await RentalRepository().fetchMyActiveRental();
    if (rental != null && (rental.isActive || rental.isPending)) {
      hasOpenRental = true;
      bikeHint = rental.isPending ? 'pending request' : 'active rental';
    }
  } catch (_) {
    // If we cannot confirm, still continue — the database RPC is the hard block.
  }

  if (!context.mounted) return;

  if (hasOpenRental) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.lock_clock_rounded, color: cs.error, size: 28),
        title: const Text('Finish your rental first'),
        content: Text(
          'You still have a $bikeHint. Return the bike and wait until an admin ends the ride before deleting your account.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  final typed = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AnimatedBuilder(
        animation: typed,
        builder: (context, _) {
          final ready = typed.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            icon: Icon(Icons.person_off_outlined, color: cs.error, size: 28),
            title: const Text('Delete account?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently removes your login, verification photos, notifications, and rental history. You cannot undo this.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: typed,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Type DELETE to confirm',
                    hintText: 'DELETE',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: ready
                      ? (_) => Navigator.of(ctx).pop(true)
                      : null,
                ),
              ],
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
                onPressed: ready ? () => Navigator.of(ctx).pop(true) : null,
                child: const Text('Delete account'),
              ),
            ],
          );
        },
      );
    },
  );
  typed.dispose();

  if (confirmed != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await AuthService.deleteMyAccount();
    if (context.mounted) Navigator.of(context).pop();
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyNetworkError(e))),
    );
  }
}
