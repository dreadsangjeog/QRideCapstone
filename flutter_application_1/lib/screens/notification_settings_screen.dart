import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/notification_service.dart';
import '../widgets/user_portal_chrome.dart';

/// Rider notification preferences (sound / vibration / banners).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;
  bool _sound = true;
  bool _vibrate = true;
  bool _banners = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await NotificationService.loadPrefs();
    if (!mounted) return;
    setState(() {
      _sound = NotificationService.soundEnabled;
      _vibrate = NotificationService.vibrationEnabled;
      _banners = NotificationService.bannersEnabled;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return UserPortalScaffold(
      title: 'Notification settings',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  'Choose how QRide alerts you on this device. Sound and vibration '
                  'use your phone’s notification volume. Silent or Do Not Disturb '
                  'mode mutes them.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 16),
                PolishedSectionCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        secondary: Icon(Icons.volume_up_rounded,
                            color: cs.primary),
                        title: const Text('Alert sound'),
                        subtitle: const Text('Play a sound with rental alerts'),
                        value: _sound,
                        onChanged: (v) async {
                          setState(() => _sound = v);
                          await NotificationService.setSoundEnabled(v);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        secondary: Icon(Icons.vibration_rounded,
                            color: cs.primary),
                        title: const Text('Vibration'),
                        subtitle: const Text('Vibrate when an alert arrives'),
                        value: _vibrate,
                        onChanged: (v) async {
                          setState(() => _vibrate = v);
                          await NotificationService.setVibrationEnabled(v);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        secondary: Icon(Icons.notifications_active_rounded,
                            color: cs.primary),
                        title: const Text('On-screen banners'),
                        subtitle: const Text(
                          'Pop up on screen. Sound and vibration still play when this is off',
                        ),
                        value: _banners,
                        onChanged: (v) async {
                          setState(() => _banners = v);
                          await NotificationService.setBannersEnabled(v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PolishedSectionCard(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: Icon(Icons.settings_rounded, color: cs.primary),
                    title: const Text('Phone notification settings'),
                    subtitle: const Text(
                      'Change system sound, importance, and channel options',
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => openAppSettings(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    if (!_sound && !_vibrate && !_banners) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Turn on sound, vibration, or banners to test an alert.',
                          ),
                        ),
                      );
                      return;
                    }
                    await NotificationService.showTestAlert();
                  },
                  icon: const Icon(Icons.notifications_active_rounded),
                  label: const Text('Test sound and vibration'),
                ),
                const SizedBox(height: 20),
                Text(
                  'You still get inbox items for approvals, time warnings, overtime, '
                  'and receipts. These toggles only control sound, vibration, and banners.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ],
            ),
    );
  }
}
