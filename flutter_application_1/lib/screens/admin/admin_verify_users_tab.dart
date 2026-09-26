import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/kyc_repository.dart';
import '../../theme/brand.dart';
import '../../widgets/qride_glass.dart';
import '../../widgets/user_portal_chrome.dart';
import 'admin_layout.dart';

/// Admin tab: search riders and review uploaded ID / selfies.
class AdminVerifyUsersTab extends StatefulWidget {
  const AdminVerifyUsersTab({super.key, this.changes});

  /// Bumps when a rider submits or updates ID verification.
  final Listenable? changes;

  @override
  State<AdminVerifyUsersTab> createState() => _AdminVerifyUsersTabState();
}

class _AdminVerifyUsersTabState extends State<AdminVerifyUsersTab> {
  final _repo = KycRepository();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  /// null = all statuses
  String? _statusFilter = 'pending';
  bool _newestFirst = false;
  late Future<List<KycPendingUser>> _future = _load();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_onOutsideChange);
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _onOutsideChange());
  }

  @override
  void didUpdateWidget(AdminVerifyUsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changes != widget.changes) {
      oldWidget.changes?.removeListener(_onOutsideChange);
      widget.changes?.addListener(_onOutsideChange);
    }
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_onOutsideChange);
    _debounce?.cancel();
    _poll?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onOutsideChange() {
    if (mounted) unawaited(_refresh());
  }

  Future<List<KycPendingUser>> _load() {
    return _repo.searchUsers(
      query: _searchCtrl.text,
      status: _statusFilter,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) unawaited(_refresh());
    });
  }

  void _setFilter(String? status) {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    unawaited(_refresh());
  }

  Future<void> _openUser(KycPendingUser u) async {
    final changed = await showAdminPage<bool>(
      context,
      maxWidth: 900,
      builder: (_) => _AdminKycReviewScreen(user: u),
    );
    if (changed == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final pad = adminPagePadding(context);
    return AdminContent(
          maxWidth: 1180,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AdminPageHeader(
                      title: 'Riders',
                      subtitle:
                          'Verify IDs and open credentials when a bike is not returned',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        setState(() {});
                        _onSearchChanged(v);
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search by name or username…',
                        filled: true,
                        fillColor: cs.surface.withValues(alpha: 0.9),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchCtrl.clear();
                                  unawaited(_refresh());
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear_rounded),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 1.4),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _FilterChip(
                                label: 'All',
                                selected: _statusFilter == null,
                                onTap: () => _setFilter(null),
                              ),
                              _FilterChip(
                                label: 'Pending',
                                selected: _statusFilter == 'pending',
                                onTap: () => _setFilter('pending'),
                              ),
                              _FilterChip(
                                label: 'Unverified',
                                selected: _statusFilter == 'unverified',
                                onTap: () => _setFilter('unverified'),
                              ),
                              _FilterChip(
                                label: 'Verified',
                                selected: _statusFilter == 'verified',
                                onTap: () => _setFilter('verified'),
                              ),
                              _FilterChip(
                                label: 'Rejected',
                                selected: _statusFilter == 'rejected',
                                onTap: () => _setFilter('rejected'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        AdminSortToggle(
                          newestFirst: _newestFirst,
                          onChanged: (newest) =>
                              setState(() => _newestFirst = newest),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: FutureBuilder<List<KycPendingUser>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return ListView(
                          children: const [
                            SizedBox(height: 140),
                            Center(child: CircularProgressIndicator()),
                          ],
                        );
                      }
                      if (snap.hasError) {
                        return ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            PolishedSectionCard(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Icon(Icons.error_outline_rounded,
                                        color: cs.error, size: 32),
                                    const SizedBox(height: 10),
                                    Text('${snap.error}',
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 14),
                                    FilledButton(
                                      onPressed: _refresh,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      final rows = [...snap.data ?? <KycPendingUser>[]];
                      if (_newestFirst) {
                        rows.sort((a, b) {
                          final at = a.createdAt ??
                              DateTime.fromMillisecondsSinceEpoch(0);
                          final bt = b.createdAt ??
                              DateTime.fromMillisecondsSinceEpoch(0);
                          return bt.compareTo(at);
                        });
                      } else {
                        rows.sort(
                          (a, b) => a.displayName
                              .toLowerCase()
                              .compareTo(b.displayName.toLowerCase()),
                        );
                      }
                      if (rows.isEmpty) {
                        return ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const SizedBox(height: 48),
                            PolishedSectionCard(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 36,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.badge_outlined,
                                      size: 40,
                                      color: cs.primary.withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _statusFilter == 'pending'
                                          ? 'No riders waiting for review'
                                          : 'No riders match this search',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Try another filter or search term.',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return ListView(
                        padding: EdgeInsets.fromLTRB(
                          pad.left,
                          8,
                          pad.right,
                          pad.bottom,
                        ),
                        children: [
                          AdminCardGrid(
                            minItemWidth: 420,
                            spacing: 12,
                            children: [
                              for (final u in rows)
                                _UserRowCard(
                                  user: u,
                                  onTap: () => _openUser(u),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: cs.primary.withValues(alpha: 0.14),
      backgroundColor: cs.surface.withValues(alpha: 0.85),
      side: BorderSide(
        color: selected
            ? cs.primary.withValues(alpha: 0.45)
            : cs.outlineVariant.withValues(alpha: 0.45),
      ),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? cs.primary : cs.onSurface,
      ),
    );
  }
}

class _UserRowCard extends StatelessWidget {
  const _UserRowCard({required this.user, required this.onTap});

  final KycPendingUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _kycStatusColor(user.status, cs);
    final hasDocs = (user.idImagePath?.isNotEmpty ?? false) ||
        (user.selfieImagePath?.isNotEmpty ?? false);

    return GlassPanel(
      radius: 18,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.person_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (user.legalName.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          user.username,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _StatusPill(
                            label: _kycStatusLabel(user.status),
                            color: color,
                          ),
                          _MetaPill(
                            icon: hasDocs
                                ? Icons.badge_outlined
                                : Icons.hide_image_outlined,
                            label: hasDocs ? 'Docs on file' : 'No docs',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminKycReviewScreen extends StatefulWidget {
  const _AdminKycReviewScreen({required this.user});

  final KycPendingUser user;

  @override
  State<_AdminKycReviewScreen> createState() => _AdminKycReviewScreenState();
}

class _AdminKycReviewScreenState extends State<_AdminKycReviewScreen> {
  final _repo = KycRepository();
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await _repo.setStatus(userId: widget.user.id, status: status);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmRevoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.gpp_bad_outlined,
            color: Theme.of(ctx).colorScheme.error),
        title: const Text('Revoke verification?'),
        content: Text(
          '${widget.user.username} will need to submit ID again before renting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok == true) await _setStatus('rejected');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final u = widget.user;
    final statusColor = _kycStatusColor(u.status, cs);
    final canReview = u.status == 'pending' || u.status == 'rejected';
    final canRevoke = u.status == 'verified';

    return Scaffold(
      backgroundColor: QrideBrand.mist,
      appBar: AppBar(
        title: const Text('Rider profile'),
        leading: adminDialogLeading(context),
        automaticallyImplyLeading: !adminInDialog(context),
        backgroundColor: QrideBrand.mist,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              PolishedSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.person_rounded,
                          color: statusColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              u.legalName.isEmpty ? u.username : u.legalName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (u.legalName.isNotEmpty)
                              Text(
                                'Username: ${u.username}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            Text(
                              'Match this name to the ID photo',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _StatusPill(
                              label: _kycStatusLabel(u.status),
                              color: statusColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PolishedSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use these credentials if a bike is not returned. '
                          'Tap any photo to enlarge and pinch to zoom.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (u.note != null && u.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                PolishedSectionCard(
                  child: ListTile(
                    leading: Icon(Icons.sticky_note_2_outlined,
                        color: cs.onSurfaceVariant),
                    title: const Text('Review note'),
                    subtitle: Text(u.note!),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const PortalSectionLabel('ID photo'),
              PolishedSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _KycPhoto(
                    path: u.idImagePath,
                    label: 'Government ID',
                    height: 220,
                    emptyIcon: Icons.badge_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const PortalSectionLabel('Live selfies'),
              PolishedSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 560;
                      final tiles = [
                        _KycPhoto(
                          path: u.selfieImagePath,
                          label: 'Front',
                          height: wide ? 160 : 140,
                          emptyIcon: Icons.face_retouching_natural_outlined,
                        ),
                        _KycPhoto(
                          path: u.selfieLeftPath,
                          label: 'Look left',
                          height: wide ? 160 : 140,
                          emptyIcon: Icons.face_outlined,
                        ),
                        _KycPhoto(
                          path: u.selfieRightPath,
                          label: 'Look right',
                          height: wide ? 160 : 140,
                          emptyIcon: Icons.face_outlined,
                        ),
                      ];
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < tiles.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: tiles[i]),
                            ],
                          ],
                        );
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            tiles[i],
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (canReview)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy ? null : () => _setStatus('rejected'),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: cs.error,
                          side: BorderSide(
                            color: cs.error.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed:
                            _busy ? null : () => _setStatus('verified'),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.verified_rounded),
                        label: Text(_busy ? 'Saving…' : 'Approve'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
              if (canRevoke)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmRevoke,
                  icon: const Icon(Icons.gpp_bad_outlined),
                  label: const Text('Revoke verification'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: cs.error,
                    side: BorderSide(color: cs.error.withValues(alpha: 0.45)),
                  ),
                ),
              if (u.status == 'unverified') ...[
                const SizedBox(height: 8),
                Text(
                  'This rider has not uploaded ID documents yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
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

class _KycPhoto extends StatelessWidget {
  const _KycPhoto({
    required this.path,
    required this.label,
    this.height = 140,
    this.emptyIcon = Icons.image_outlined,
  });

  final String? path;
  final String label;
  final double height;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (path == null || path!.isEmpty)
          _emptyBox(context)
        else
          FutureBuilder<String?>(
            future: KycRepository().signedUrlOrNull(path!),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return _frame(
                  context,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              }
              final url = snap.data;
              if (url == null) return _emptyBox(context, failed: true);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openFull(context, url, label),
                  borderRadius: BorderRadius.circular(14),
                  child: Ink(
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                _emptyInner(context, failed: true),
                          ),
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.zoom_in_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _frame(BuildContext context, {required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: child,
    );
  }

  Widget _emptyBox(BuildContext context, {bool failed = false}) {
    return _frame(context, child: _emptyInner(context, failed: failed));
  }

  Widget _emptyInner(BuildContext context, {bool failed = false}) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          failed ? Icons.broken_image_outlined : emptyIcon,
          size: 28,
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(height: 8),
        Text(
          failed ? 'Could not load' : 'Not uploaded',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  void _openFull(BuildContext context, String url, String title) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 20,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
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

Color _kycStatusColor(String status, ColorScheme cs) {
  return switch (status) {
    'verified' => const Color(0xFF16A34A),
    'pending' => const Color(0xFFD97706),
    'rejected' => cs.error,
    _ => cs.onSurfaceVariant,
  };
}

String _kycStatusLabel(String status) {
  return switch (status) {
    'verified' => 'Verified',
    'pending' => 'Pending review',
    'rejected' => 'Rejected',
    'unverified' => 'Not submitted',
    _ => status,
  };
}
