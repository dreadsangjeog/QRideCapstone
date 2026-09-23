import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../utils/account_management.dart';
import '../../utils/logout_guard.dart';
import '../../services/kyc_repository.dart';
import '../../theme/brand.dart';
import '../../widgets/user_portal_chrome.dart';
import 'kyc_liveness_screen.dart';

class KycWizardScreen extends StatefulWidget {
  const KycWizardScreen({
    super.key,
    this.onSubmitted,
    this.rejectedNote,
  });

  final VoidCallback? onSubmitted;
  final String? rejectedNote;

  @override
  State<KycWizardScreen> createState() => _KycWizardScreenState();
}

class _KycWizardScreenState extends State<KycWizardScreen> {
  final _repo = KycRepository();
  final _page = PageController();
  int _step = 0;

  Uint8List? _idBytes;
  Uint8List? _selfieFrontBytes;
  Uint8List? _selfieLeftBytes;
  Uint8List? _selfieRightBytes;
  bool _busy = false;
  String? _error;

  bool get _hasSelfies =>
      _selfieFrontBytes != null &&
      _selfieLeftBytes != null &&
      _selfieRightBytes != null;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _goTo(int step) async {
    setState(() {
      _step = step;
      _error = null;
    });
    await _page.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickId({required bool camera}) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 88,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _idBytes = bytes;
      _error = null;
    });
  }

  Future<void> _takeSelfie() async {
    if (kIsWeb) {
      setState(() {
        _error = 'Live selfie works on the Android app, not in the browser.';
      });
      return;
    }
    final shots = await Navigator.of(context).push<KycLivenessShots>(
      MaterialPageRoute(builder: (_) => const KycLivenessScreen()),
    );
    if (shots == null) return;
    final front = await shots.front.readAsBytes();
    final left = await shots.left.readAsBytes();
    final right = await shots.right.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selfieFrontBytes = front;
      _selfieLeftBytes = left;
      _selfieRightBytes = right;
      _error = null;
    });
    await _goTo(3);
  }

  Future<void> _submit() async {
    if (_idBytes == null || !_hasSelfies) {
      setState(() => _error = 'Finish your ID photo and live selfie first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.submit(
        idBytes: _idBytes!,
        selfieFrontBytes: _selfieFrontBytes!,
        selfieLeftBytes: _selfieLeftBytes!,
        selfieRightBytes: _selfieRightBytes!,
      );
      if (!mounted) return;
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rejected = widget.rejectedNote?.trim();

    return Scaffold(
      backgroundColor: QrideBrand.mist,
      appBar: AppBar(
        title: const Text('Identity verification'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => confirmAndSignOut(context),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: _StepHeader(step: _step),
          ),
          if (rejected != null && rejected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _Notice(
                icon: Icons.info_outline_rounded,
                color: cs.error,
                title: 'Previous submission was rejected',
                body: rejected,
              ),
            ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _IntroPage(
                  onContinue: () => _goTo(1),
                  onLogout: () => confirmAndSignOut(context),
                  onDeleteAccount: () => confirmAndDeleteAccount(context),
                ),
                _IdPage(
                  bytes: _idBytes,
                  busy: _busy,
                  onCamera: () => _pickId(camera: true),
                  onGallery: () => _pickId(camera: false),
                  onNext: _idBytes == null ? null : () => _goTo(2),
                  onBack: () => _goTo(0),
                ),
                _SelfiePage(
                  hasSelfies: _hasSelfies,
                  front: _selfieFrontBytes,
                  left: _selfieLeftBytes,
                  right: _selfieRightBytes,
                  busy: _busy,
                  onStart: _takeSelfie,
                  onNext: _hasSelfies ? () => _goTo(3) : null,
                  onBack: () => _goTo(1),
                ),
                _ReviewPage(
                  idBytes: _idBytes,
                  front: _selfieFrontBytes,
                  left: _selfieLeftBytes,
                  right: _selfieRightBytes,
                  busy: _busy,
                  error: _error,
                  onSubmit: _submit,
                  onBack: () => _goTo(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Why', 'ID', 'Selfie', 'Review'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: i <= step
                    ? QrideBrand.accent
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.6),
              ),
            ),
          _Dot(index: i, active: i == step, done: i < step, label: labels[i]),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.index,
    required this.active,
    required this.done,
    required this.label,
  });

  final int index;
  final bool active;
  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = done || active ? QrideBrand.accent : cs.outlineVariant;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done || active ? QrideBrand.accent : cs.surface,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.6),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: active ? Colors.white : cs.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.onContinue,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final VoidCallback onContinue;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'Verify once, then you can rent',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'QRide needs to know who is riding the bike. This protects the campus fleet if a bike is not returned.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        const _InfoTile(
          icon: Icons.badge_outlined,
          title: 'Photo of your ID',
          body: 'School or government ID. Use the camera so the text is readable.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.face_retouching_natural_outlined,
          title: 'Live face check',
          body:
              'Blink, then turn your head left and right. A printed photo or screenshot will not pass.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.verified_user_outlined,
          title: 'Admin review',
          body:
              'Staff confirm your ID matches the live selfies. You can rent after you are approved.',
        ),
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.lock_outline_rounded,
          color: QrideBrand.accent,
          title: 'Your documents stay private',
          body:
              'ID and selfies are stored securely and used only for rider verification — not for ads or sharing.',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onContinue,
          child: const Text('Start verification'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onLogout,
          child: const Text('Not now — log out'),
        ),
        TextButton(
          onPressed: onDeleteAccount,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _IdPage extends StatelessWidget {
  const _IdPage({
    required this.bytes,
    required this.busy,
    required this.onCamera,
    required this.onGallery,
    required this.onNext,
    required this.onBack,
  });

  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'Photograph your ID',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Place the card on a flat surface. Avoid glare. All four corners should be visible.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        PolishedSectionCard(
          child: bytes == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      Icon(Icons.badge_outlined, size: 40, color: cs.primary),
                      const SizedBox(height: 10),
                      const Text(
                        'No ID photo yet',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: Image.memory(
                        bytes!,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              color: Color(0xFF16A34A), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'ID photo captured',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onCamera,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(bytes == null ? 'Open camera' : 'Retake with camera'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: busy ? null : onGallery,
          child: const Text('Use a photo already on this phone'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelfiePage extends StatelessWidget {
  const _SelfiePage({
    required this.hasSelfies,
    required this.front,
    required this.left,
    required this.right,
    required this.busy,
    required this.onStart,
    required this.onNext,
    required this.onBack,
  });

  final bool hasSelfies;
  final Uint8List? front;
  final Uint8List? left;
  final Uint8List? right;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'Live face check',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'This proves you are a real person in front of the camera — not a photo or another phone screen.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        const _InfoTile(
          icon: Icons.visibility_outlined,
          title: '1. Face the camera and blink',
          body: 'Front selfie is taken right after the blink.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.rotate_left_rounded,
          title: '2. Turn your head left',
          body: 'We watch the head move. A still picture will not pass.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.rotate_right_rounded,
          title: '3. Turn your head right',
          body: 'Same check the other way, then you are done.',
        ),
        if (hasSelfies) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _ShotThumb(bytes: front!, label: 'Front')),
              const SizedBox(width: 8),
              Expanded(child: _ShotThumb(bytes: left!, label: 'Left')),
              const SizedBox(width: 8),
              Expanded(child: _ShotThumb(bytes: right!, label: 'Right')),
            ],
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : onStart,
          icon: const Icon(Icons.face_retouching_natural_outlined),
          label: Text(hasSelfies ? 'Redo live selfie' : 'Start live selfie'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: onNext,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({
    required this.idBytes,
    required this.front,
    required this.left,
    required this.right,
    required this.busy,
    required this.error,
    required this.onSubmit,
    required this.onBack,
  });

  final Uint8List? idBytes;
  final Uint8List? front;
  final Uint8List? left;
  final Uint8List? right;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = idBytes != null && front != null && left != null && right != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Text(
          'Review and submit',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Make sure the ID is readable and the selfies are clearly you. An admin will compare them.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        if (idBytes != null)
          PolishedSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Text(
                    'ID photo',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(idBytes!, height: 160, fit: BoxFit.cover),
                  ),
                ),
              ],
            ),
          ),
        if (front != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _ShotThumb(bytes: front!, label: 'Front')),
              const SizedBox(width: 8),
              Expanded(child: _ShotThumb(bytes: left!, label: 'Left')),
              const SizedBox(width: 8),
              Expanded(child: _ShotThumb(bytes: right!, label: 'Right')),
            ],
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 14),
          Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy || !ready ? null : onSubmit,
          child: busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Submit for review'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: busy ? null : onBack,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PolishedSectionCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: QrideBrand.accent.withValues(alpha: 0.12),
          child: Icon(icon, color: QrideBrand.accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          body,
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShotThumb extends StatelessWidget {
  const _ShotThumb({required this.bytes, required this.label});

  final Uint8List bytes;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, height: 110, fit: BoxFit.cover),
        ),
      ],
    );
  }
}
