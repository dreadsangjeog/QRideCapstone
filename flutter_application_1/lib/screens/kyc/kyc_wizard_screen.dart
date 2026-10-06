import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utils/account_management.dart';
import '../../utils/auth_validators.dart';
import '../../utils/logout_guard.dart';
import '../../services/kyc_auto_match.dart';
import '../../services/kyc_repository.dart';
import '../../theme/brand.dart';
import '../../widgets/birthdate_picker.dart';
import '../../widgets/user_portal_chrome.dart';
import 'kyc_face_match_panel.dart';
import 'kyc_id_capture_screen.dart';
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
  final _nameForm = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _birthdate = TextEditingController();
  int _step = 0;

  Uint8List? _idBytes;
  Uint8List? _selfieFrontBytes;
  bool _busy = false;
  String? _error;
  bool _nameLocked = false;
  bool _waitingForStaff = false;
  Future<KycAutoMatchResult>? _faceWork;

  bool get _hasSelfies => _selfieFrontBytes != null;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    try {
      final p = await _repo.fetchMine();
      if (!mounted) return;
      _firstName.text = p.firstName ?? '';
      _middleName.text = p.middleName ?? '';
      _lastName.text = p.lastName ?? '';
      _birthdate.text = (p.birthdate ?? '').length >= 10
          ? p.birthdate!.substring(0, 10)
          : (p.birthdate ?? '');
      setState(() {
        _nameLocked = p.personalDetailsLocked;
        _waitingForStaff = p.isPending;
      });
    } catch (_) {}
  }

  Future<bool> _saveName() async {
    if (_nameLocked) return true;
    if (!(_nameForm.currentState?.validate() ?? false)) return false;
    await _repo.updateLegalName(
      firstName: _firstName.text,
      middleName: _middleName.text,
      lastName: _lastName.text,
      birthdate: _birthdate.text,
    );
    return true;
  }

  @override
  void dispose() {
    _page.dispose();
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _birthdate.dispose();
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

  Future<void> _pickId() async {
    if (kIsWeb) {
      setState(() {
        _error = 'ID capture works on the Android app, not in the browser.';
      });
      return;
    }
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => KycIdCaptureScreen(
          firstName: _firstName.text,
          lastName: _lastName.text,
        ),
      ),
    );
    if (bytes == null || !mounted) return;
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
    if (!mounted) return;
    setState(() {
      _selfieFrontBytes = front;
      _error = null;
    });
    await _goTo(3);
  }

  Future<void> _persistNameIfValid() async {
    if (_nameLocked) return;
    final firstBad = AuthValidators.legalName(
      _firstName.text,
      label: 'First name',
    );
    final lastBad = AuthValidators.legalName(
      _lastName.text,
      label: 'Last name',
    );
    if (firstBad != null || lastBad != null) return;
    try {
      await _repo.updateLegalName(
        firstName: _firstName.text,
        middleName: _middleName.text,
        lastName: _lastName.text,
        birthdate: AuthValidators.birthdate(_birthdate.text) == null
            ? _birthdate.text
            : null,
      );
    } catch (_) {}
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
      await _persistNameIfValid();
      await _repo.submit(
        idBytes: _idBytes!,
        selfieFrontBytes: _selfieFrontBytes!,
      );
      final work = KycAutoMatch.reviewFaces(
        idBytes: _idBytes!,
        selfieBytes: _selfieFrontBytes!,
      ).catchError(
        (_) => const KycAutoMatchResult(
          nameMatch: true,
          photoMatch: false,
          note:
              'Could not compare the faces. Try the selfie again in better light.',
        ),
      );
      if (!mounted) return;
      setState(() => _faceWork = work);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onFaceFinished(KycAutoMatchResult match) async {
    try {
      if (match.photoMatch) {
        await _repo.holdForStaffReview(note: _staffNote(match));
      } else {
        await _repo.applyAutoReview(
          nameMatch: true,
          photoMatch: false,
          note: match.note,
        );
      }
      if (!mounted) return;
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _faceWork = null;
        _busy = false;
        _error = match.photoMatch ? e.toString() : match.note;
      });
    }
  }

  static String _staffNote(KycAutoMatchResult match) {
    final score = match.faceScore;
    final scoreText = score == null ? '' : ' (score ${score.toStringAsFixed(2)})';
    return switch (match.faceVerdict) {
      KycFaceVerdict.match =>
        'Name matched the ID. Face check: strong match$scoreText. Waiting for staff to verify.',
      _ when score == null =>
        'Name matched the ID. The app could not compare the faces on this phone. Compare the ID photo and selfie before approving.',
      _ =>
        'Name matched the ID. Face check: unsure$scoreText. Compare the ID photo and selfie closely before approving.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final rejected = widget.rejectedNote?.trim();
    if (_waitingForStaff) {
      return Scaffold(
        backgroundColor: QrideBrand.mist,
        appBar: AppBar(
          title: const Text('Identity verification'),
          actions: [
            TextButton(
              onPressed: () => confirmAndSignOut(context),
              child: const Text('Log out'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text(
              'Waiting for staff',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your ID is already submitted. Name and birthdate stay as entered. You do not need to continue verification.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _LockedSummary(
              firstName: _firstName.text,
              middleName: _middleName.text,
              lastName: _lastName.text,
              birthdate: _birthdate.text,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to QRide'),
            ),
          ],
        ),
      );
    }

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
      body: Stack(
        children: [
          Column(
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
                  formKey: _nameForm,
                  firstName: _firstName,
                  middleName: _middleName,
                  lastName: _lastName,
                  birthdate: _birthdate,
                  nameLocked: _nameLocked,
                  error: _error,
                  onContinue: () async {
                    try {
                      if (!await _saveName()) return;
                      if (mounted) await _goTo(1);
                    } catch (e) {
                      if (mounted) {
                        setState(() => _error = e.toString());
                      }
                    }
                  },
                  onLogout: () => confirmAndSignOut(context),
                  onDeleteAccount: () => confirmAndDeleteAccount(context),
                ),
                _IdPage(
                  bytes: _idBytes,
                  busy: _busy,
                  onCamera: _pickId,
                  onNext: _idBytes == null ? null : () => _goTo(2),
                  onBack: () => _goTo(0),
                ),
                _SelfiePage(
                  hasSelfies: _hasSelfies,
                  front: _selfieFrontBytes,
                  busy: _busy,
                  onStart: _takeSelfie,
                  onNext: _hasSelfies ? () => _goTo(3) : null,
                  onBack: () => _goTo(1),
                ),
                _ReviewPage(
                  idBytes: _idBytes,
                  front: _selfieFrontBytes,
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
          if (_faceWork != null &&
              _idBytes != null &&
              _selfieFrontBytes != null)
            Positioned.fill(
              child: KycFaceMatchPanel(
                idPhoto: _idBytes!,
                selfie: _selfieFrontBytes!,
                work: _faceWork!,
                onFinished: _onFaceFinished,
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
    const labels = ['Name', 'ID', 'Selfie', 'Review'];
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
    required this.formKey,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.birthdate,
    required this.nameLocked,
    this.error,
    required this.onContinue,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstName;
  final TextEditingController middleName;
  final TextEditingController lastName;
  final TextEditingController birthdate;
  final bool nameLocked;
  final String? error;
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
        Form(
          key: formKey,
          child: nameLocked
              ? _LockedSummary(
                  firstName: firstName.text,
                  middleName: middleName.text,
                  lastName: lastName.text,
                  birthdate: birthdate.text,
                )
              : Column(
            children: [
              TextFormField(
                controller: firstName,
                enabled: !nameLocked,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'First name'),
                validator: (v) => AuthValidators.legalName(v, label: 'First name'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: middleName,
                enabled: !nameLocked,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Middle name (optional)',
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
                enabled: !nameLocked,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Last name'),
                validator: (v) => AuthValidators.legalName(v, label: 'Last name'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: birthdate,
                enabled: !nameLocked,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Birthdate',
                  suffixIcon: Icon(Icons.calendar_today_rounded),
                ),
                validator: AuthValidators.birthdate,
                onTap: nameLocked
                    ? null
                    : () async {
                  final initial = DateTime.tryParse(birthdate.text) ??
                      DateTime(2004, 1, 1);
                  final picked = await showBirthdatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                    startWithYear: birthdate.text.isEmpty,
                  );
                  if (picked == null) return;
                  final m = picked.month.toString().padLeft(2, '0');
                  final d = picked.day.toString().padLeft(2, '0');
                  birthdate.text = '${picked.year}-$m-$d';
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          nameLocked
              ? 'These details already matched your ID. Only staff can change them after review.'
              : 'Type first and last name as they appear on the ID. Birthdate is saved on your account but is not used to match the ID.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        const _InfoTile(
          icon: Icons.badge_outlined,
          title: 'Photo of your ID',
          body:
              'Line the card up in the frame. Use horizontal or vertical to match a government or student ID.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.face_retouching_natural_outlined,
          title: 'Live face check',
          body:
              'Blink, then turn your head when asked. A printed photo or another screen will not pass.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.verified_user_outlined,
          title: 'Automatic check',
          body:
              'QRide matches first name and last name separately to the ID. Birthdate is not used, so student IDs are fine.',
        ),
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.lock_outline_rounded,
          color: QrideBrand.accent,
          title: 'Your documents stay private',
          body:
              'ID and selfies are stored securely and used only for rider verification — not for ads or sharing.',
        ),
        if (error != null && error!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
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

class _LockedSummary extends StatelessWidget {
  const _LockedSummary({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.birthdate,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String birthdate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String shown(String value) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? '—' : trimmed;
    }

    Widget row(String label, String value) {
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
              shown(value),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('First name', firstName),
        row('Middle name', middleName),
        row('Last name', lastName),
        row('Birthdate', birthdate),
      ],
    );
  }
}

class _IdPage extends StatelessWidget {
  const _IdPage({
    required this.bytes,
    required this.busy,
    required this.onCamera,
    required this.onNext,
    required this.onBack,
  });

  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCamera;
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
          'Place a school or government ID in the frame. Edges do not need to be perfect — as long as the printed face and name are readable.',
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
          icon: const Icon(Icons.crop_free_rounded),
          label: Text(bytes == null ? 'Align ID in frame' : 'Retake ID photo'),
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
    required this.busy,
    required this.onStart,
    required this.onNext,
    required this.onBack,
  });

  final bool hasSelfies;
  final Uint8List? front;
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
          title: '1. Blink once',
          body: 'Eyes must close and open. A printed photo cannot do that.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.rotate_90_degrees_ccw_rounded,
          title: '2. Turn when asked',
          body: 'Left or right, chosen at random. We watch the head move.',
        ),
        const SizedBox(height: 10),
        const _InfoTile(
          icon: Icons.photo_camera_outlined,
          title: '3. One live photo',
          body: 'Look back at the camera. That selfie is matched to your ID.',
        ),
        if (hasSelfies && front != null) ...[
          const SizedBox(height: 16),
          _ShotThumb(bytes: front!, label: 'Live selfie'),
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
    required this.busy,
    required this.error,
    required this.onSubmit,
    required this.onBack,
  });

  final Uint8List? idBytes;
  final Uint8List? front;
  final bool busy;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = idBytes != null && front != null;
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
          'Your name already matched the ID. This step checks the face. If it matches, staff do the final verification.',
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
          _ShotThumb(bytes: front!, label: 'Live selfie'),
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
              : const Text('Match faces and verify'),
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
