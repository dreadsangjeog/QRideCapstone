import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/admin_repository.dart';
import '../services/auth_service.dart';
import '../services/kyc_repository.dart';
import '../utils/auth_validators.dart';
import '../widgets/birthdate_picker.dart';
import '../widgets/user_portal_chrome.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/admin_generate_qr_screen.dart';
import 'kyc/kyc_scope.dart';
import 'legal/terms_screen.dart';
import 'notification_settings_screen.dart';
import 'user_account_settings_screen.dart';

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
  final _kyc = KycRepository();
  final _nameFormKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _birthdate = TextEditingController();
  KycProfile? _profile;
  bool _savingName = false;

  @override
  void initState() {
    super.initState();
    _refreshAdminRole();
    unawaited(_loadProfile());
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

  Future<void> _loadProfile() async {
    try {
      final profile = await _kyc.fetchMine();
      if (!mounted) return;
      _firstName.text = profile.firstName ?? '';
      _middleName.text = profile.middleName ?? '';
      _lastName.text = profile.lastName ?? '';
      _birthdate.text = (profile.birthdate ?? '').length >= 10
          ? profile.birthdate!.substring(0, 10)
          : (profile.birthdate ?? '');
      setState(() => _profile = profile);
    } catch (_) {}
  }

  Future<void> _saveName() async {
    if (_profile?.personalDetailsLocked == true) return;
    if (!(_nameFormKey.currentState?.validate() ?? false)) return;
    setState(() => _savingName = true);
    try {
      await _kyc.updateLegalName(
        firstName: _firstName.text,
        middleName: _middleName.text,
        lastName: _lastName.text,
        birthdate: _birthdate.text,
      );
      if (!mounted) return;
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name saved. It will be matched to your ID.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save name: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _birthdate.dispose();
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
              Text(
                'Your account',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage alerts, theme, and sign-out from here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
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
              const SizedBox(height: 18),
              _LegalNameCard(
                formKey: _nameFormKey,
                firstName: _firstName,
                middleName: _middleName,
                lastName: _lastName,
                birthdate: _birthdate,
                locked: _profile?.personalDetailsLocked == true,
                saving: _savingName,
                onSave: _saveName,
              ),
              if (_profile != null && _profile!.isPending) ...[
                const SizedBox(height: 12),
                const _WaitingReviewNotice(),
              ] else if (_profile != null && !_profile!.isVerified) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final kyc = KycScope.maybeOf(context);
                    if (kyc != null && kyc.profile.needsAction) {
                      await kyc.openWizard(context);
                      await _loadProfile();
                    }
                  },
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('Continue ID verification'),
                ),
              ],
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
                        Icons.notifications_outlined,
                        color: cs.primary,
                      ),
                      title: const Text('Notification settings'),
                      subtitle: Text(
                        'Sound, vibration, and banners',
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
                            builder: (_) =>
                                const NotificationSettingsScreen(),
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
                        vertical: 4,
                      ),
                      leading: Icon(
                        Icons.gavel_outlined,
                        color: cs.primary,
                      ),
                      title: const Text('Terms & privacy'),
                      subtitle: Text(
                        'Rental rules, logout warning, and data use',
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
                            builder: (_) => const TermsScreen(),
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
              const PortalSectionLabel('Account'),
              PolishedSectionCard(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: Icon(Icons.manage_accounts_outlined, color: cs.primary),
                  title: const Text('Account settings'),
                  subtitle: Text(
                    'Appearance, delete account, and log out',
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
                        builder: (_) => const UserAccountSettingsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LegalNameCard extends StatelessWidget {
  const _LegalNameCard({
    required this.formKey,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.birthdate,
    required this.locked,
    required this.saving,
    required this.onSave,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstName;
  final TextEditingController middleName;
  final TextEditingController lastName;
  final TextEditingController birthdate;
  final bool locked;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PortalSectionLabel('Legal name'),
        PolishedSectionCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    locked
                        ? 'Submitted with your ID. These details stay as staff review them.'
                        : 'Used to match the ID you upload. You can edit it until you photograph your ID.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (locked) ...[
                    _LockedDetail(label: 'First name', value: firstName.text),
                    _LockedDetail(
                      label: 'Middle name',
                      value: middleName.text.trim().isEmpty
                          ? '—'
                          : middleName.text.trim(),
                    ),
                    _LockedDetail(label: 'Last name', value: lastName.text),
                    _LockedDetail(label: 'Birthdate', value: birthdate.text),
                  ] else ...[
                  TextFormField(
                    controller: firstName,
                    enabled: !locked && !saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: (v) =>
                        AuthValidators.legalName(v, label: 'First name'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: middleName,
                    enabled: !locked && !saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Middle name',
                      hintText: 'Optional',
                    ),
                    validator: (v) => AuthValidators.legalName(
                      v,
                      label: 'Middle name',
                      required: false,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: lastName,
                    enabled: !locked && !saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: (v) =>
                        AuthValidators.legalName(v, label: 'Last name'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: birthdate,
                    enabled: !locked && !saving,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Birthdate',
                      prefixIcon: Icon(Icons.cake_outlined),
                    ),
                    validator: AuthValidators.birthdate,
                    onTap: locked || saving
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final initial = DateTime.tryParse(birthdate.text) ??
                                DateTime(now.year - 18, now.month, now.day);
                            final picked = await showBirthdatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(1920),
                              lastDate: DateTime(now.year, now.month, now.day)
                                  .subtract(const Duration(days: 1)),
                            );
                            if (picked == null) return;
                            final m = picked.month.toString().padLeft(2, '0');
                            final d = picked.day.toString().padLeft(2, '0');
                            birthdate.text = '${picked.year}-$m-$d';
                          },
                  ),
                  ],
                  if (!locked) ...[
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: saving ? null : onSave,
                      child: Text(saving ? 'Saving…' : 'Save name'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockedDetail extends StatelessWidget {
  const _LockedDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            shown,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _WaitingReviewNotice extends StatelessWidget {
  const _WaitingReviewNotice();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PolishedSectionCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_top_rounded, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Waiting for staff',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your ID is submitted. Nothing else to verify. Staff will notify you when you can rent.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
