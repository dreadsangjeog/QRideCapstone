import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/bike.dart';
import '../services/admin_repository.dart';

/// Opens the device gallery (file picker on web).
Future<Uint8List?> pickBikePhotoBytes() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 85,
  );
  if (file == null) return null;
  return file.readAsBytes();
}

/// Network or in-memory bike photo. Empty state is a bike glyph.
class BikePhotoView extends StatelessWidget {
  const BikePhotoView({
    super.key,
    this.url,
    this.bytes,
    this.size = 56,
    this.radius = 14,
    this.fit = BoxFit.cover,
    this.iconSize,
  });

  final String? url;
  final Uint8List? bytes;
  final double size;
  final double radius;
  final BoxFit fit;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasBytes = bytes != null && bytes!.isNotEmpty;
    final hasUrl = (url ?? '').isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: hasBytes
            ? Image.memory(bytes!, fit: fit)
            : hasUrl
                ? Image.network(
                    url!,
                    fit: fit,
                    errorBuilder: (_, _, _) => _placeholder(cs),
                  )
                : _placeholder(cs),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
      child: Icon(
        Icons.pedal_bike_rounded,
        color: cs.onSurfaceVariant,
        size: iconSize ?? (size * 0.42),
      ),
    );
  }
}

/// Admin sheet: preview, upload/replace, or remove a bike photo.
Future<Bike?> showBikePhotoEditor(
  BuildContext context, {
  required AdminRepository repo,
  required Bike bike,
}) {
  return showModalBottomSheet<Bike>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _BikePhotoEditorSheet(repo: repo, bike: bike),
  );
}

class _BikePhotoEditorSheet extends StatefulWidget {
  const _BikePhotoEditorSheet({required this.repo, required this.bike});

  final AdminRepository repo;
  final Bike bike;

  @override
  State<_BikePhotoEditorSheet> createState() => _BikePhotoEditorSheetState();
}

class _BikePhotoEditorSheetState extends State<_BikePhotoEditorSheet> {
  late Bike _bike;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bike = widget.bike;
  }

  Future<void> _pickAndUpload() async {
    final bytes = await pickBikePhotoBytes();
    if (bytes == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repo.uploadBikePhoto(
        bikeId: _bike.id,
        bytes: bytes,
        previousPath: _bike.photoPath,
      );
      if (!mounted) return;
      setState(() {
        _bike = updated;
        _busy = false;
      });
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save photo. $e')),
      );
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.repo.removeBikePhoto(
        bikeId: _bike.id,
        previousPath: _bike.photoPath,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove photo. $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final url = AdminRepository.publicPhotoUrl(_bike.photoPath);
    final pad = MediaQuery.paddingOf(context).bottom;
    final name = _bike.label?.trim().isNotEmpty == true
        ? _bike.label!
        : 'Bike ${_bike.code}';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bike photo',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: BikePhotoView(
              url: url,
              size: 220,
              radius: 20,
              iconSize: 72,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndUpload,
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_bike.hasPhoto ? 'Replace photo' : 'Upload photo'),
          ),
          if (_bike.hasPhoto) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _remove,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Remove photo'),
            ),
          ],
        ],
      ),
    );
  }
}
