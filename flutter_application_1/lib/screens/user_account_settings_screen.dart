import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../utils/account_management.dart';
import '../utils/logout_guard.dart';
import '../widgets/user_portal_chrome.dart';
import 'notification_settings_screen.dart';

/// Delete account, logout, theme, and notification preferences.
class UserAccountSettingsScreen extends StatelessWidget {
  const UserAccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return UserPortalScaffold(
      title: 'Account settings',
      showBell: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const PortalSectionLabel('Preferences'),
          PolishedSectionCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  leading: Icon(Icons.notifications_outlined, color: cs.primary),
                  title: const Text('Notification settings'),
                  subtitle: Text(
                    'Sound, vibration, and banners',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotificationSettingsScreen(),
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
                        setThemeMode(on ? ThemeMode.dark : ThemeMode.light);
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const PortalSectionLabel('Account'),
          PolishedSectionCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: Icon(Icons.person_off_outlined, color: cs.error),
                  title: Text(
                    'Delete account',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Permanently remove your login and personal data',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  onTap: () => confirmAndDeleteAccount(context),
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
                    vertical: 8,
                  ),
                  leading: Icon(Icons.logout_rounded, color: cs.error),
                  title: Text(
                    'Log out',
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Stay signed out on this device',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  onTap: () => confirmAndSignOut(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
