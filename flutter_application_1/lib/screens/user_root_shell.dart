import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ride_location_controller.dart';
import '../theme/brand.dart';
import '../widgets/user_portal_chrome.dart';
import 'kyc/kyc_scope.dart';
import 'legal/terms_screen.dart';
import 'notifications_screen.dart';
import 'user_account_settings_screen.dart';
import 'user_active_rental_screen.dart';
import 'user_history_screen.dart';
import 'user_home_map_screen.dart';
import 'user_profile_screen.dart';
import 'user_scan_screen.dart';

class UserRootShell extends StatefulWidget {
  const UserRootShell({super.key});

  static const routeName = '/user';

  @override
  State<UserRootShell> createState() => _UserRootShellState();
}

class _UserRootShellState extends State<UserRootShell> {
  /// 0 map, 1 active (kept alive for GPS), 2 history, 3 profile
  int _index = 0;
  final _inbox = NotificationInboxController();
  final _rideLocation = RideLocationController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _inbox.start();
    unawaited(_rideLocation.start());
  }

  @override
  void dispose() {
    _inbox.dispose();
    unawaited(_rideLocation.dispose());
    super.dispose();
  }

  void _goHome() => setState(() => _index = 0);

  void _openPage(int index) => setState(() => _index = index);

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  Future<void> _openScan() async {
    final kyc = KycScope.maybeOf(context);
    if (kyc != null && !kyc.canUseFeatures) {
      if (kyc.profile.needsAction) {
        await kyc.openWizard(context);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Staff are still checking your ID. You can look around, but you cannot rent yet.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const UserScanScreen(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  Future<void> _onDrawerPick(int value) async {
    Navigator.of(context).pop();
    if (value == 4) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const TermsScreen()));
      return;
    }
    if (value == 5) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const UserAccountSettingsScreen(),
        ),
      );
      return;
    }
    if (value == 6) {
      final kyc = KycScope.maybeOf(context);
      if (kyc == null) return;
      if (kyc.profile.needsAction) {
        await kyc.openWizard(context);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Staff are still checking your ID. You will get a notification when you are verified.',
          ),
        ),
      );
      return;
    }
    _openPage(value);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationInboxScope(
      controller: _inbox,
      child: RideLocationScope(
        controller: _rideLocation,
        child: RiderNavScope(
          goHome: _goHome,
          openPage: _openPage,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: _RiderDrawer(currentIndex: _index, onPick: _onDrawerPick),
            drawerEnableOpenDragGesture: _index == 0,
            body: Stack(
              fit: StackFit.expand,
              children: [
                IndexedStack(
                  index: _index,
                  children: const [
                    UserHomeMapScreen(),
                    UserActiveRentalScreen(),
                    UserHistoryScreen(),
                    UserProfileScreen(),
                  ],
                ),
                if (_index == 0) ...[
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 6,
                    left: 12,
                    child: GlassCircleButton(
                      tooltip: 'Menu',
                      icon: Icons.menu_rounded,
                      onTap: _openDrawer,
                    ),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 6,
                    right: 12,
                    child: const _MapBell(),
                  ),
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + 62,
                    left: 16,
                    right: 16,
                    child: const _KycLockBanner(),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _ScanDock(onTap: _openScan),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapBell extends StatelessWidget {
  const _MapBell();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? const Color(0xFF1B2433)
        : Colors.white.withValues(alpha: 0.92);
    final rim = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.78);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: bg,
            shape: CircleBorder(side: BorderSide(color: rim)),
            child: NotificationBellButton(
              color: isDark ? Colors.white : const Color(0xFF111827),
              alignBelow: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _RiderDrawer extends StatelessWidget {
  const _RiderDrawer({required this.currentIndex, required this.onPick});

  final int currentIndex;
  final ValueChanged<int> onPick;

  String _displayName(User? user) {
    if (user == null) return 'Rider';
    final meta = user.userMetadata;
    final u = meta?['username']?.toString().trim();
    if (u != null && u.isNotEmpty) return u;
    final n = meta?['name']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Rider';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final user = Supabase.instance.client.auth.currentUser;
    final name = _displayName(user);
    final email = user?.email?.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';

    return Drawer(
      width: 300,
      backgroundColor: isDark ? const Color(0xFF101827) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              child: Row(
                children: [
                  const Text(
                    'QRide',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: () => onPick(3),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: QrideBrand.accent.withValues(
                        alpha: 0.16,
                      ),
                      foregroundColor: QrideBrand.accent,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (email == null || email.isEmpty)
                                ? 'View profile'
                                : email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: cs.outlineVariant.withValues(alpha: 0.45)),
            ),
            _DrawerItem(
              icon: Icons.history_rounded,
              label: 'History',
              selected: currentIndex == 2,
              onTap: () => onPick(2),
            ),
            _DrawerItem(
              icon: Icons.directions_bike_rounded,
              label: 'My rental',
              selected: currentIndex == 1,
              onTap: () => onPick(1),
            ),
            _DrawerItem(
              icon: Icons.gavel_outlined,
              label: 'Terms & rules',
              selected: false,
              onTap: () => onPick(4),
            ),
            if (KycScope.maybeOf(context)?.canUseFeatures == false)
              _DrawerItem(
                icon: Icons.verified_user_outlined,
                label: KycScope.of(context).profile.needsAction
                    ? 'Verify ID'
                    : 'Verification status',
                selected: false,
                onTap: () => onPick(6),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: cs.outlineVariant.withValues(alpha: 0.45)),
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Account settings',
              selected: false,
              onTap: () => onPick(5),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
      child: Material(
        color: selected
            ? QrideBrand.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? QrideBrand.accent : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 15,
                      color: selected ? QrideBrand.accent : cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KycLockBanner extends StatelessWidget {
  const _KycLockBanner();

  @override
  Widget build(BuildContext context) {
    final kyc = KycScope.maybeOf(context);
    if (kyc == null || kyc.canUseFeatures) return const SizedBox.shrink();
    final p = kyc.profile;
    final pending = p.isPending;
    final title = pending
        ? 'Waiting for staff'
        : p.isRejected
            ? 'Verification needs another try'
            : 'Verify your ID to rent';
    final body = pending
        ? 'You can look around. Renting unlocks after staff approve your ID.'
        : p.isRejected
            ? (p.note?.trim().isNotEmpty == true
                ? p.note!
                : 'Photograph your ID again, then complete a new live selfie.')
            : 'Scan and rent stay locked until your ID is verified.';
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: p.needsAction ? () => kyc.openWizard(context) : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(
                pending
                    ? Icons.hourglass_top_rounded
                    : Icons.verified_user_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      body,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.3,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (p.needsAction)
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanDock extends StatelessWidget {
  const _ScanDock({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: QrideBrand.accent.withValues(alpha: 0.34),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.all(Radius.circular(999)),
              color: QrideBrand.accent,
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Scan',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
