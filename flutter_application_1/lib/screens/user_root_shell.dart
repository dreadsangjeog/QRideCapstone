import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/brand.dart';
import '../widgets/user_portal_chrome.dart';
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _inbox.start();
  }

  @override
  void dispose() {
    _inbox.dispose();
    super.dispose();
  }

  void _goHome() => setState(() => _index = 0);

  void _openPage(int index) => setState(() => _index = index);

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  Future<void> _openScan() async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const UserScanScreen(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  Future<void> _onDrawerPick(int value) async {
    Navigator.of(context).pop();
    if (value == 4) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
      );
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
    _openPage(value);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationInboxScope(
      controller: _inbox,
      child: RiderNavScope(
        goHome: _goHome,
        openPage: _openPage,
        child: Scaffold(
          key: _scaffoldKey,
          drawer: _RiderDrawer(
            currentIndex: _index,
            onPick: _onDrawerPick,
          ),
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
    );
  }
}

class _MapBell extends StatelessWidget {
  const _MapBell();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark
          ? const Color(0xE6182233)
          : Colors.white.withValues(alpha: 0.96),
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      child: NotificationBellButton(
        color: isDark ? const Color(0xFFE8EEF6) : const Color(0xFF111827),
        alignBelow: true,
      ),
    );
  }
}

class _RiderDrawer extends StatelessWidget {
  const _RiderDrawer({
    required this.currentIndex,
    required this.onPick,
  });

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
                      backgroundColor: QrideBrand.accent.withValues(alpha: 0.16),
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
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
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
              label: 'Active rental',
              selected: currentIndex == 1,
              onTap: () => onPick(1),
            ),
            _DrawerItem(
              icon: Icons.gavel_outlined,
              label: 'Terms & rules',
              selected: false,
              onTap: () => onPick(4),
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
                  Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
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
