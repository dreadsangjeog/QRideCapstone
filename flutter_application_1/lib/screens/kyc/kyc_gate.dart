import 'package:flutter/material.dart';

import '../../services/kyc_repository.dart';
import '../../utils/account_management.dart';
import '../../utils/logout_guard.dart';
import '../../theme/brand.dart';
import '../../widgets/user_portal_chrome.dart';
import 'kyc_wizard_screen.dart';

class KycGate extends StatefulWidget {
  const KycGate({super.key, required this.child});

  final Widget child;

  @override
  State<KycGate> createState() => _KycGateState();
}

class _KycGateState extends State<KycGate> {
  final _repo = KycRepository();
  KycProfile? _profile;
  String? _error;
  bool _retryRejected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.fetchMine();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _error = null;
        if (p.isPending) _retryRejected = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (_error != null && p == null) {
      return _StatusScaffold(
        title: 'Verification',
        icon: Icons.wifi_off_rounded,
        heading: 'Could not load status',
        body: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (p.isVerified) return widget.child;
    if (p.isPending) {
      return _StatusScaffold(
        title: 'Under review',
        icon: Icons.hourglass_top_rounded,
        heading: 'We’re reviewing your ID',
        body:
            'An admin is comparing your ID photo with your live selfies. You can rent a bike as soon as you are approved.',
        actionLabel: 'Refresh status',
        onAction: _load,
      );
    }
    if (p.isRejected && !_retryRejected) {
      return _StatusScaffold(
        title: 'Needs another try',
        icon: Icons.gpp_bad_outlined,
        heading: 'Verification was not approved',
        body: (p.note != null && p.note!.trim().isNotEmpty)
            ? p.note!
            : 'Please photograph your ID again and complete a new live selfie.',
        actionLabel: 'Start again',
        onAction: () => setState(() => _retryRejected = true),
      );
    }
    return KycWizardScreen(
      onSubmitted: _load,
      rejectedNote: p.isRejected ? p.note : null,
    );
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.title,
    required this.icon,
    required this.heading,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final IconData icon;
  final String heading;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      backgroundColor: QrideBrand.mist,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => confirmAndSignOut(context),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: PolishedSectionCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: QrideBrand.accent.withValues(alpha: 0.12),
                      child: Icon(icon, size: 32, color: QrideBrand.accent),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      heading,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => confirmAndSignOut(context),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Log out'),
                    ),
                    TextButton(
                      onPressed: () => confirmAndDeleteAccount(context),
                      child: const Text('Delete account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
