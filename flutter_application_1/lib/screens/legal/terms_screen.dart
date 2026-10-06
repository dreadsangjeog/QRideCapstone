import 'package:flutter/material.dart';

import '../../theme/brand.dart';
import '../../widgets/qride_glass.dart';
import '../../widgets/user_portal_chrome.dart';

/// Rider terms of use and privacy notice.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, this.requireAccept = false});

  static const routeName = '/terms';

  /// If true, shows an Accept button that pops `true`.
  final bool requireAccept;

  @override
  Widget build(BuildContext context) {
    return UserPortalScaffold(
      title: 'Terms & Privacy',
      showBell: false,
      body: Column(
        children: [
          const Expanded(child: _TermsContent()),
          if (requireAccept) const _TermsAcceptBar(),
        ],
      ),
    );
  }
}

const _lastUpdated = 'October 2026';

class _Highlight {
  const _Highlight(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const _highlights = <_Highlight>[
  _Highlight(
    Icons.verified_user_outlined,
    'Verify your ID first',
    'Staff check your ID and a live face scan before your first ride.',
  ),
  _Highlight(
    Icons.timer_outlined,
    'Staff start and end every ride',
    'The timer starts when they approve and stops when they end the ride.',
  ),
  _Highlight(
    Icons.payments_outlined,
    'Pay for the time you book',
    'Overtime costs 1.5× the hourly rate. Amounts round to the nearest peso.',
  ),
  _Highlight(
    Icons.location_on_outlined,
    'Location only during a ride',
    'GPS is shared from approval until staff end the ride.',
  ),
  _Highlight(
    Icons.lock_outline_rounded,
    'Your data stays private',
    'Only you and authorized staff can see it, and it is never sold.',
  ),
  _Highlight(
    Icons.person_remove_outlined,
    'Leave whenever you want',
    'Delete your account once no rental is open.',
  ),
];

class _Section {
  const _Section({
    required this.icon,
    required this.title,
    required this.summary,
    required this.points,
  });

  final IconData icon;
  final String title;
  final String summary;
  final List<String> points;
}

const _sections = <_Section>[
  _Section(
    icon: Icons.person_outline_rounded,
    title: 'Your account',
    summary: 'Signing up and keeping your account safe',
    points: [
      'Sign up with your legal name, your birthdate, and a Gmail address you can open.',
      'Keep your password private and use only your own account. You are responsible for rentals made with it.',
      'You can look around right away. Renting unlocks once staff verify your ID.',
    ],
  ),
  _Section(
    icon: Icons.pedal_bike_rounded,
    title: 'Renting a bike',
    summary: 'From scanning the bike to bringing it back',
    points: [
      'Scan the QR code on the bike or type its code, then choose a time from 30 minutes to 8 hours.',
      'Your request waits for staff approval. You can cancel it while it is still pending.',
      'The timer starts when staff approve. From your request until staff end the ride, the bike is your responsibility.',
      'Before your booked time ends you can add time, at least 15 minutes at a time. Once overtime starts, the ride can no longer be extended.',
      'You cannot end a ride yourself. Bring the bike back so staff can end it.',
    ],
  ),
  _Section(
    icon: Icons.payments_outlined,
    title: 'Fees and overtime',
    summary: 'What you pay and how it is counted',
    points: [
      'You pay for the full time you book. Returning the bike early does not lower the fee.',
      'Adding time raises the total to match the new booked time.',
      'After the booked time ends, overtime is charged at 1.5× the hourly rate.',
      'Amounts that are not a whole peso, including penalties, are rounded to the nearest peso.',
      'You see the amount before you send a request and on your ride screen. Staff record it when they end the ride. QRide never charges a card.',
      'If staff change the hourly rate, ended rentals keep their recorded amount. New requests use the new rate, and an open ride uses it for the rest of the booked time and any overtime.',
    ],
  ),
  _Section(
    icon: Icons.location_on_outlined,
    title: 'Location during a ride',
    summary: 'Shared only from approval until the ride ends',
    points: [
      'QRide does not share your location when you have no rental, or while a request is still waiting.',
      'After you request a bike, a notice stays on so sharing can start the moment staff approve, even if QRide is closed.',
      'During an active ride, QRide reads GPS about every 3 seconds, along with your direction of travel, so staff can see the bike on the map. When you stop, direction can come from the phone compass.',
      'A “Rental in progress” notice stays on. Sharing continues if you switch apps, lock the phone, or swipe QRide away. Keep location and internet on, and leave the notice in place.',
      'QRide asks for location only while the app is in use. It never asks for “Allow all the time” or a battery exception.',
      'If updates stop, for example because the phone or GPS is off, staff are notified and can still see the last known point.',
    ],
  ),
  _Section(
    icon: Icons.badge_outlined,
    title: 'Identity verification',
    summary: 'How staff confirm it is really you',
    points: [
      'You submit your name, birthdate, a photo of your ID, and a live face check with a front view and side turns.',
      'Staff review them before verifying your account. If something does not match, you can submit again.',
      'These images are stored privately. They are used only to confirm who you are and to help recover a bike that is not returned.',
    ],
  ),
  _Section(
    icon: Icons.lock_outline_rounded,
    title: 'Privacy and your data',
    summary: 'What we keep, who can see it, and your rights',
    points: [
      'We keep your name, birthdate, username, email, ID images, rental history, ride locations, and notifications.',
      'Only you and authorized QRide staff can see this data. It is stored in a secured database and is never sold or used for advertising.',
      'QRide follows the Philippine Data Privacy Act of 2012 (RA 10173). You can ask staff to show you or correct your data, and you may file a complaint with the National Privacy Commission.',
      'To delete your account, open Account settings → Delete account once no request is pending and no ride is active. This removes your login, ID images, notifications, and ride locations, and cannot be undone.',
      'Settled rentals stay in staff history and reports, including the rider name and the amount charged, and are marked as a deleted account.',
    ],
  ),
  _Section(
    icon: Icons.notifications_outlined,
    title: 'Alerts',
    summary: 'What QRide tells you, and what staff see',
    points: [
      'You get alerts when staff approve or decline a request, when about 5 minutes are left, when overtime starts, and when your ride record is ready.',
      'Staff are notified if you log out during an open rental, or if the bike’s location stops updating.',
      'You can turn off alert sound, vibration, or on-screen banners from the menu → Notification settings, or from Profile. Your inbox still keeps every alert.',
    ],
  ),
  _Section(
    icon: Icons.health_and_safety_outlined,
    title: 'Riding responsibly',
    summary: 'Rules for every ride',
    points: [
      'Ride safely and follow campus traffic rules.',
      'Only you may ride the bike you rented. Do not lend it to anyone or let anyone use your account.',
      'Tell staff right away about damage, a flat tire, or an accident.',
      'Do not log out while a request is pending or a ride is active. Staff are notified and may review your ID documents and last known location. Leaving QRide or locking the phone is not logging out.',
      'Staff may decline a request or end a ride if these rules are not followed.',
    ],
  ),
  _Section(
    icon: Icons.update_rounded,
    title: 'Changes and contact',
    summary: 'Updates to these terms and how to reach us',
    points: [
      'When these terms change, the date at the top changes too. Using QRide after an update means you accept the new version.',
      'Ended rentals keep the amounts recorded when they ended.',
      'Questions about a rental, your data, or these terms? Ask QRide staff.',
    ],
  ),
];

class _TermsContent extends StatefulWidget {
  const _TermsContent();

  @override
  State<_TermsContent> createState() => _TermsContentState();
}

class _TermsContentState extends State<_TermsContent> {
  final Set<int> _open = {};

  bool get _allOpen => _open.length == _sections.length;

  void _toggle(int index) {
    setState(() {
      if (!_open.remove(index)) _open.add(index);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_allOpen) {
        _open.clear();
      } else {
        _open.addAll(List.generate(_sections.length, (i) => i));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const _TermsHeader(),
        const SizedBox(height: 22),
        const _GroupLabel('The short version'),
        const _HighlightsCard(),
        const SizedBox(height: 12),
        const _SignedInCallout(),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: _GroupLabel('Full terms')),
            TextButton(
              onPressed: _toggleAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_allOpen ? 'Collapse all' : 'Expand all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < _sections.length; i++) ...[
          _SectionCard(
            number: i + 1,
            section: _sections[i],
            open: _open.contains(i),
            onToggle: () => _toggle(i),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        Text(
          'QRide campus bike rental · Last updated $_lastUpdated',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TermsHeader extends StatelessWidget {
  const _TermsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [QrideBrand.accent, QrideBrand.accentDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: QrideBrand.accent.withValues(alpha: 0.32),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                Icons.gavel_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Terms of Use & Privacy Notice',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'How renting works, what you pay, and how we handle your data. '
            'Creating an account or renting a bike means you agree to these terms.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(icon: Icons.event_outlined, label: 'Updated $_lastUpdated'),
              _Pill(icon: Icons.shield_outlined, label: 'Data Privacy Act (RA 10173)'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.size = 40, this.color});

  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: tone, size: size * 0.52),
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassPanel(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        children: [
          for (final h in _highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconTile(icon: h.icon, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          h.body,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SignedInCallout extends StatelessWidget {
  const _SignedInCallout();

  static const _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    return GlassPanel(
      radius: 20,
      tint: isDark
          ? const Color(0xFF2B2416)
          : const Color(0xFFFFF4DE).withValues(alpha: 0.9),
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _IconTile(
            icon: Icons.warning_amber_rounded,
            size: 36,
            color: _amber,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay signed in until the ride ends',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Logging out while a request is pending or a ride is active '
                  'notifies staff. Switching apps or locking your phone is fine.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.number,
    required this.section,
    required this.open,
    required this.onToggle,
  });

  final int number;
  final _Section section;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return GlassPanel(
      radius: 20,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                child: Row(
                  children: [
                    _IconTile(icon: section.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$number. ${section.title}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            section.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        for (final point in section.points) _Point(point),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ),
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
    final isDark = cs.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101827) : Colors.white,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _agreed = !_agreed),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _agreed,
                          onChanged: (v) =>
                              setState(() => _agreed = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'I have read and agree to the Terms of Use and Privacy Notice.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed:
                      _agreed ? () => Navigator.of(context).pop(true) : null,
                  child: const Text(
                    'Agree and continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
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
