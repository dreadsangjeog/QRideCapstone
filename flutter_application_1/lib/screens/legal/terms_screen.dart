import 'package:flutter/material.dart';

import '../../theme/brand.dart';
import '../../widgets/user_portal_chrome.dart';

/// Campus terms, privacy, and rental rules.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, this.requireAccept = false});

  static const routeName = '/terms';

  /// If true, shows an Accept button that pops `true`.
  final bool requireAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Terms & privacy'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text(
                  'QRide terms of use',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'By creating an account or using QRide you agree to these terms. Last updated October 2026.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                const _TermCard(
                  icon: Icons.gavel_outlined,
                  title: 'How a rental works',
                  body:
                      'You can rent only after staff verify your identity. Scan the bike QR or enter the code on the bike, then choose a time from 30 minutes up to 8 hours. The request stays pending until staff approve it, or you cancel it. The timer starts when staff approve. You are responsible for the bike from that request until staff end the ride. You cannot end the ride yourself. While it is active you may add at least 15 more minutes. Ride safely and return the bike for staff to close the rental.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.payments_outlined,
                  title: 'Fees',
                  body:
                      'You pay for the full time you choose. Ending the rental early does not lower the fee. Adding time increases the charge for the new total. After the planned time, the overtime penalty is 1.5× the hourly rate. If a charge is not a whole peso, including the penalty, it is rounded to the nearest peso. The amount due is shown before you send a request and on your ride screen. Staff record that amount when they end the ride. The app does not charge a card. If staff change the hourly rate, rentals already ended keep the amount that was recorded. From that moment, new requests use the new rate, and a ride that is still open uses the new rate for the rest of the booked time and for overtime.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.location_on_outlined,
                  title: 'Location during a ride',
                  body:
                      'Location sharing starts only after staff approve the rental, and stops when they end it. We do not track you while you are signed in with no active rental, or while a request is still pending. During an active ride, QRide reads GPS about every 3 seconds and the direction of travel so staff can see the bike on the map. While the bike is moving, direction comes from travel. While it is stopped, direction can come from the phone compass. A “Rental in progress” notice stays on. Sharing continues if you leave QRide, switch apps, lock the screen, or put the phone in a pocket. Keep location and internet on, and leave that notice in place. QRide asks only for location while you use the app. It does not ask for “Allow all the time” or a battery-optimization exception. If the phone is off, GPS is off, or updates stop, staff are notified and can still see the last point.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.warning_amber_rounded,
                  title: 'Logging out during a rental',
                  body:
                      'Logging out while a request is pending or a rental is active notifies staff. They may review your identity documents and last known location. Do not log out until the bike is back and staff have ended the ride. Leaving the app or locking the phone is not logging out, and location sharing is meant to continue.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.badge_outlined,
                  title: 'Identity verification',
                  body:
                      'Before you can rent, you submit your name, birthdate, a photo of your ID, and a live face check, including a front view and side turns. Staff review this before your account is verified. Those images are stored privately and used only to confirm who you are and to recover a bike that is not returned. They are not sold or used for advertising.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Your privacy',
                  body:
                      'We store your username, email, verification images, notifications, rental history, and ride locations on a secured database. Only you and authorized QRide staff can access this data. You can delete your account in Profile → Delete account after every rental is settled. You cannot delete it while a request is pending or a rental is active. Deleting removes your login, verification photos, notifications, and ride locations. Settled rentals stay in staff reports and history without your name, shown as a deleted account. This cannot be undone.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.notifications_outlined,
                  title: 'Alerts',
                  body:
                      'QRide may send in-app and device alerts when staff approve or reject a request, when about 5 minutes remain, when overtime starts, and for your ride record. Staff are also notified if you log out during an open rental, or if the bike’s location stops updating.',
                ),
              ],
            ),
          ),
          if (requireAccept) const _TermsAcceptBar(),
        ],
      ),
    );
  }
}

class _TermsAcceptBar extends StatefulWidget {
  const _TermsAcceptBar();

  @override
  State<_TermsAcceptBar> createState() => _TermsAcceptBarState();
}

class _TermsAcceptBarState extends State<_TermsAcceptBar> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                title: const Text(
                  'I agree to the Terms & Privacy',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton(
                onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
                child: const Text('Agree and continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  const _TermCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return PolishedSectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        leading: CircleAvatar(
          backgroundColor: QrideBrand.accent.withValues(alpha: 0.12),
          child: Icon(icon, color: QrideBrand.accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(body, style: const TextStyle(height: 1.4)),
        ),
      ),
    );
  }
}

/// Compact “agree to terms” control used on register.
class TermsAgreeRow extends StatelessWidget {
  const TermsAgreeRow({
    super.key,
    required this.agreed,
    required this.onChanged,
  });

  final bool agreed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: agreed,
          onChanged: (v) => onChanged(v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'I have read and agree to the ',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TermsScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Terms & Privacy',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                      decorationColor: cs.primary,
                    ),
                  ),
                ),
                Text(
                  '. Logging out during an active rental may be treated as suspicious activity.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TermsFooterLink extends StatelessWidget {
  const TermsFooterLink({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.4,
        ),
        children: [
          const TextSpan(text: 'By continuing you agree to the '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TermsScreen(),
                  ),
                );
              },
              child: Text(
                'Terms & Privacy',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
