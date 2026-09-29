import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/bike.dart';
import '../../services/admin_repository.dart';
import '../../services/auth_service.dart';
import '../../utils/bike_qr_payload.dart';
import '../../widgets/bike_photo.dart';
import '../../widgets/login_scene_backdrop.dart';
import '../../widgets/qride_glass.dart';
import 'admin_layout.dart';

class AdminGenerateQrScreen extends StatefulWidget {
  const AdminGenerateQrScreen({
    super.key,
    required this.repo,
    this.initialBike,
  });

  final AdminRepository repo;
  final Bike? initialBike;

  @override
  State<AdminGenerateQrScreen> createState() => _AdminGenerateQrScreenState();
}

class _AdminGenerateQrScreenState extends State<AdminGenerateQrScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qrPreviewKey = GlobalKey();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _labelCtrl;

  late String _status;
  String? _payload;
  bool _busy = false;
  /// True after a new bike was inserted this session; tells the bikes tab to refresh.
  bool _refreshListOnPop = false;
  /// Form locked after successful create (QR is tied to the saved row).
  bool _committed = false;
  bool _adminGatePassed = false;
  bool _generatingCode = false;
  Bike? _bike;
  Uint8List? _pendingPhoto;
  bool _photoBusy = false;

  bool get _isExisting => widget.initialBike != null;

  @override
  void initState() {
    super.initState();
    final b = widget.initialBike;
    _codeCtrl = TextEditingController(text: b?.code ?? '');
    _labelCtrl = TextEditingController(text: b?.label ?? '');
    _status = b?.status ?? 'available';
    _bike = b;

    if (b != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _payload = bikeQrPayloadFromCode(b.code));
        _scrollQrIntoView();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAdmin());
  }

  Future<void> _ensureAdmin() async {
    final ok = await AuthService.isAdmin();
    if (!mounted) return;
    if (!ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Access denied'),
          content: const Text(
            'Adding bikes and generating QR codes requires an administrator account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _adminGatePassed = true);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  bool get _fieldsLocked => _isExisting || _committed;

  Future<void> _saveAndShowQr() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _codeCtrl.text.trim();
    final label = _labelCtrl.text.trim();

    final duplicate = await widget.repo.fetchBikeByCode(code);
    if (!mounted) return;
    if (duplicate != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'The code "$code" is already used by another bike. Choose a different code.',
          ),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final created = await widget.repo.createBike(
        code: code,
        label: label,
        status: _status,
      );
      Bike saved = created;
      if (_pendingPhoto != null) {
        saved = await widget.repo.uploadBikePhoto(
          bikeId: created.id,
          bytes: _pendingPhoto!,
        );
      }
      if (!mounted) return;
      setState(() {
        _bike = saved;
        _pendingPhoto = null;
        _committed = true;
        _payload = bikeQrPayloadFromCode(code);
        _refreshListOnPop = true;
      });
      _scrollQrIntoView();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bike saved. The scannable QR is on this page (black & white square).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatSaveError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatSaveError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('23505') ||
        s.contains('unique') ||
        s.contains('duplicate')) {
      return 'That bike code is already in use. Choose a different code.';
    }
    return 'Could not save bike: $e';
  }

  void _scrollQrIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _qrPreviewKey.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.1,
        );
      }
    });
  }

  Future<void> _generateUniqueCode() async {
    if (_fieldsLocked || _generatingCode) return;
    setState(() => _generatingCode = true);
    try {
      final code = await widget.repo.generateUniqueBikeCode();
      if (!mounted) return;
      setState(() {
        _codeCtrl.text = code;
        _payload = null;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate code: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingCode = false);
    }
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickBikePhotoBytes();
    if (bytes == null || !mounted) return;
    final saved = _bike;
    if (saved == null) {
      setState(() {
        _pendingPhoto = bytes;
        _refreshListOnPop = true;
      });
      return;
    }
    setState(() => _photoBusy = true);
    try {
      final updated = await widget.repo.uploadBikePhoto(
        bikeId: saved.id,
        bytes: bytes,
        previousPath: saved.photoPath,
      );
      if (!mounted) return;
      setState(() {
        _bike = updated;
        _pendingPhoto = null;
        _refreshListOnPop = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save photo. $e')),
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    final saved = _bike;
    if (saved == null) {
      setState(() => _pendingPhoto = null);
      return;
    }
    setState(() => _photoBusy = true);
    try {
      final updated = await widget.repo.removeBikePhoto(
        bikeId: saved.id,
        previousPath: saved.photoPath,
      );
      if (!mounted) return;
      setState(() {
        _bike = updated;
        _pendingPhoto = null;
        _refreshListOnPop = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove photo. $e')),
      );
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _copyPayload() async {
    final p = _payload;
    if (p == null || p.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: p));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR payload copied to clipboard')),
    );
  }

  Widget _photoField(ThemeData theme, ColorScheme cs) {
    final url = AdminRepository.publicPhotoUrl(_bike?.photoPath);
    final hasLocal = _pendingPhoto != null;
    final hasPhoto = hasLocal || (_bike?.hasPhoto ?? false);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            BikePhotoView(
              url: hasLocal ? null : url,
              bytes: _pendingPhoto,
              size: 72,
              radius: 12,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bike photo',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPhoto
                        ? 'Shown to staff and to riders when they scan.'
                        : 'Optional. Helps staff and riders recognize this bike.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: (_busy || _photoBusy) ? null : _pickPhoto,
                        icon: _photoBusy
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              )
                            : Icon(
                                hasPhoto
                                    ? Icons.sync_rounded
                                    : Icons.add_photo_alternate_outlined,
                                size: 18,
                              ),
                        label: Text(hasPhoto ? 'Replace' : 'Upload'),
                      ),
                      if (hasPhoto)
                        TextButton(
                          onPressed:
                              (_busy || _photoBusy) ? null : _removePhoto,
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget shell(Widget child) {
      if (adminInDialog(context)) return child;
      return AdminGlassScene(child: child);
    }

    if (!_adminGatePassed) {
      return shell(
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('New bike & QR'),
            backgroundColor: Colors.transparent,
            foregroundColor: cs.onSurface,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: const GlassAppBarBackdrop(),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return shell(
      PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_refreshListOnPop);
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          tooltip: adminInDialog(context) ? 'Close' : 'Back',
          icon: Icon(
            adminInDialog(context)
                ? Icons.close_rounded
                : Icons.arrow_back_rounded,
          ),
          onPressed: () => Navigator.of(context).pop(_refreshListOnPop),
        ),
        title: Text(_isExisting ? 'Bike QR' : 'New bike & QR'),
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const GlassAppBarBackdrop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (_isExisting)
            Card(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This bike is already in the database. The QR encodes its code so riders can start a rental.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              'Complete all fields, then tap Save. The app will create the bike in Supabase and then show a printable black-and-white QR (generated on this device—no extra service).',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (_committed) ...[
              const SizedBox(height: 12),
              Card(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Bike saved. Scroll up if needed to see the large QR square above the form.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onPrimaryContainer,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
          if (_payload != null) ...[
            const SizedBox(height: 8),
            Text(
              'Scannable QR (bike code)',
              key: _qrPreviewKey,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _labelCtrl.text.trim().isNotEmpty
                                ? _labelCtrl.text.trim()
                                : 'Bike ${_payload!}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Code: ${_payload!} · Status: $_status',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: QrImageView(
                            data: _payload!,
                            version: QrVersions.auto,
                            size: 240,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF000000),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF000000),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      _payload!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _copyPayload,
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      label: const Text('Copy encoded value'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Screenshot or print this code and attach it to the bike.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _codeCtrl,
                      readOnly: _fieldsLocked,
                      enabled: !_fieldsLocked,
                      decoration: InputDecoration(
                        labelText: 'Bike code',
                        hintText: 'e.g. BIKE-XK2P9M',
                        border: const OutlineInputBorder(),
                        helperText: _fieldsLocked
                            ? 'Unique ID on the physical bike. Encoded in the QR.'
                            : 'Unique in Supabase. Tap shuffle to generate a random free code.',
                        suffixIcon: _fieldsLocked
                            ? null
                            : IconButton(
                                tooltip: 'Generate unique code',
                                icon: _generatingCode
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      )
                                    : const Icon(Icons.shuffle_rounded),
                                onPressed:
                                    _generatingCode ? null : _generateUniqueCode,
                              ),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter a bike code';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _labelCtrl,
                      readOnly: _fieldsLocked,
                      enabled: !_fieldsLocked,
                      decoration: InputDecoration(
                        labelText: 'Bike name / location',
                        hintText: 'e.g. North rack #3',
                        border: const OutlineInputBorder(),
                        helperText: _isExisting
                            ? null
                            : 'A short name so staff can recognize this bike.',
                      ),
                      validator: (v) {
                        if (_isExisting) return null;
                        if (v == null || v.trim().isEmpty) {
                          return 'Enter a name or location for this bike';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _photoField(theme, cs),
                    const SizedBox(height: 16),
                    if (_status == 'rented')
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                          helperText:
                              'Rented is set automatically when a rider’s request is approved.',
                        ),
                        child: Text(
                          'Rented',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        key: ValueKey(_status),
                        initialValue:
                            _status == 'maintenance' ? 'maintenance' : 'available',
                        decoration: InputDecoration(
                          labelText: 'Status',
                          border: const OutlineInputBorder(),
                          helperText: _isExisting
                              ? null
                              : 'New bikes start as Available. Rented is set when a rider rents.',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'available',
                            child: Text('Available'),
                          ),
                          DropdownMenuItem(
                            value: 'maintenance',
                            child: Text('Maintenance'),
                          ),
                        ],
                        onChanged: _fieldsLocked
                            ? null
                            : (v) {
                                if (v != null) {
                                  setState(() => _status = v);
                                }
                              },
                      ),
                    if (!_isExisting) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: (_busy || _committed) ? null : _saveAndShowQr,
                        icon: _busy
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _committed
                              ? 'Bike saved'
                              : 'Save bike & show QR',
                        ),
                      ),
                    ],
                  ],
                ),
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
