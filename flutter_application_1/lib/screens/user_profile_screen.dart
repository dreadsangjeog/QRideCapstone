import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../main.dart' show themeNotifier;
import '../services/admin_repository.dart';
import '../services/auth_service.dart';
import '../widgets/user_portal_chrome.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/admin_generate_qr_screen.dart';

part 'user_profile_widgets.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  StreamSubscription<AuthState>? _authSub;
  bool _adminResolved = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _refreshAdminRole();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _refreshAdminRole();
    });
  }

  Future<void> _refreshAdminRole() async {
    final admin = await AuthService.isAdmin();
    if (!mounted) return;
    setState(() {
      _isAdmin = admin;
      _adminResolved = true;
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  String _displayName(User? user) {
    if (user == null) return 'Guest';
    final meta = user.userMetadata;
    final u = meta?['username']?.toString().trim();
    if (u != null && u.isNotEmpty) return u;
    final n = meta?['name']?.toString().trim();
    if (n != null && n.isNotEmpty) return n;
    return 'Rider';
  }

  String _emailLine(User? user) {
    final e = user?.email?.trim();
    if (e == null || e.isEmpty) return 'No email on file';
    return e;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final client = Supabase.instance.client;

    return UserPortalScaffold(
      title: 'Profile',
      body: StreamBuilder<AuthState>(
        stream: client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final user = client.auth.currentUser;
          final name = _displayName(user);
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              PolishedSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                              color: cs.primary.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 34,
                          backgroundColor: cs.primaryContainer,
                          foregroundColor: cs.onPrimaryContainer,
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),
                                if (_adminResolved && _isAdmin) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Admin',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _emailLine(user),
                              style: theme.textTheme.bodyMedium?.copyWith(
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
              ),
              const SizedBox(height: 28),
              const PortalSectionLabel('Settings'),
              PolishedSectionCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.notifications_active_rounded,
                        color: cs.primary,
                      ),
                      title: const Text('Notifications'),
                      subtitle: Text(
                        'Rental alerts are active',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            icon: Icon(
                              Icons.notifications_active_rounded,
                              color: cs.primary,
                              size: 32,
                            ),
                            title: const Text('Rental notifications'),
                            content: const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You will automatically receive alerts for:',
                                ),
                                SizedBox(height: 12),
                                _NotifRow(
                                  icon: Icons.check_circle_outline,
                                  text: 'Rental approved by admin',
                                ),
                                _NotifRow(
                                  icon: Icons.timer_outlined,
                                  text: '5-minute warning before time runs out',
                                ),
                                _NotifRow(
                                  icon: Icons.warning_amber_rounded,
                                  text: 'Overtime started — penalty accruing',
                                ),
                                _NotifRow(
                                  icon: Icons.receipt_long_outlined,
                                  text: 'Rental ended with cost receipt',
                                ),
                                _NotifRow(
                                  icon: Icons.cancel_outlined,
                                  text: 'Rental request declined',
                                ),
                              ],
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text('Got it'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      indent: 18,
                      endIndent: 18,
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeNotifier,
                      builder: (context, mode, _) {
                        final isDark = mode == ThemeMode.dark;
                        return SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 2,
                          ),
                          secondary: Icon(
                            isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            color: cs.primary,
                          ),
                          title: const Text('Dark mode'),
                          subtitle: Text(
                            isDark ? 'Dark theme enabled' : 'Light theme active',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          value: isDark,
                          activeThumbColor: cs.primary,
                          onChanged: (on) {
                            themeNotifier.value =
                                on ? ThemeMode.dark : ThemeMode.light;
                          },
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      indent: 18,
                      endIndent: 18,
                      color: cs.outlineVariant.withValues(alpha: 0.45),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.info_outline_rounded,
                        color: cs.primary,
                      ),
                      title: const Text('About QRide'),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'QRide',
                          applicationVersion: '1.0',
                          applicationIcon: Icon(
                            Icons.directions_bike_rounded,
                            size: 48,
                            color: cs.primary,
                          ),
                          children: const [
                            Text(
                              'Campus bike sharing with QR check-in and live location during rentals.',
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_adminResolved && _isAdmin) ...[
                const SizedBox(height: 24),
                const PortalSectionLabel('Administration'),
                PolishedSectionCard(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        leading: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: cs.primary,
                        ),
                        title: const Text('Admin dashboard'),
                        subtitle: Text(
                          'Bikes, active rentals, live map, and reports',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AdminDashboardScreen(),
                            ),
                          );
                        },
                      ),
                      Divider(
                        height: 1,
                        indent: 18,
                        endIndent: 18,
                        color: cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        leading: Icon(
                          Icons.qr_code_2_rounded,
                          color: cs.primary,
                        ),
                        title: const Text('New bike & QR code'),
                        subtitle: Text(
                          'Register a bike in the database and print its QR label',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AdminGenerateQrScreen(
                                repo: AdminRepository(),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Material(
                color: cs.errorContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.error.withValues(alpha: 0.28),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    leading: Icon(Icons.logout_rounded, color: cs.error),
                    title: Text(
                      'Log out',
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          icon: Icon(
                            Icons.logout_rounded,
                            color: cs.error,
                            size: 28,
                          ),
                          title: const Text('Log out?'),
                          content: const Text(
                            'You will be returned to the login screen.',
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
                              child: const Text('Log out'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await AuthService.signOut();
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
