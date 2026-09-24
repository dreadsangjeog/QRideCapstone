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
                  'By creating an account or using QRide you agree to these terms. Last updated September 2026.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                const _TermCard(
                  icon: Icons.gavel_outlined,
                  title: 'Campus ride rules',
                  body:
                      'Bikes are for campus use only. Ride safely, return the bike on time, and do not leave it unattended outside an approved area. You are responsible for the bike while your rental is active or pending.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.warning_amber_rounded,
                  title: 'Logging out during a rental',
                  body:
                      'If you log out, close the app, turn off the phone, or disconnect from the internet while a rental is pending or active, QRide may treat that as suspicious activity. Admins can review your identity documents and last known location. Do not log out until you have returned the bike and the rental has ended.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.location_on_outlined,
                  title: 'Location during a ride',
                  body:
                      'While a rental is active we collect your GPS location about every 3 seconds so staff can see the bike on the admin map. Location sharing stops when the rental ends. We do not track you when you are not renting.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.badge_outlined,
                  title: 'Identity verification',
                  body:
                      'You must complete ID and live-face verification before renting. Photos of your ID and selfies are stored privately and used only to confirm who you are and to recover a bike that is not returned. They are not sold or used for advertising.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Your privacy',
                  body:
                      'We store your username, email, verification images, rental history, and ride locations on a secured database. Only you and authorized QRide administrators can access this data. You can delete your account in Profile → Delete account after all rentals are settled. That removes your login, verification photos, and personal ride records.',
                ),
                const SizedBox(height: 10),
                const _TermCard(
                  icon: Icons.notifications_outlined,
                  title: 'Alerts',
                  body:
                      'QRide may send in-app and device alerts for approvals, time remaining, overtime, and receipts. If your signal drops during a ride, administrators may be notified so they can check the bike.',
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
