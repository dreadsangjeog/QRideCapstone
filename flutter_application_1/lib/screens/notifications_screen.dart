import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_repository.dart';
import '../services/notification_service.dart';
import 'notification_settings_screen.dart';

/// Long-lived inbox listener + unread badge for rider or admin shells.
class NotificationInboxController extends ChangeNotifier {
  NotificationInboxController();

  final _repo = NotificationRepository();
  RealtimeChannel? _channel;
  int unread = 0;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refreshUnread();
    if (_disposed || !_started) return;
    _channel?.unsubscribe();
    _channel = _repo.subscribeMine(onInsert: _onInsert);
  }

  Future<void> refreshUnread() async {
    try {
      final count = await _repo.unreadCount();
      if (_disposed) return;
      unread = count;
      notifyListeners();
    } catch (e) {
      debugPrint('notification unread failed: $e');
    }
  }

  void _onInsert(AppNotification n) {
    if (_disposed) return;
    unread += 1;
    notifyListeners();
    if (n.type == 'rental_five_min' || n.type == 'rental_overtime') {
      return;
    }
    unawaited(NotificationService.showInboxBanner(n));
  }

  Future<void> stop() async {
    await _channel?.unsubscribe();
    _channel = null;
    _started = false;
    unread = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _channel?.unsubscribe();
    _channel = null;
    super.dispose();
  }
}

class NotificationInboxScope extends InheritedNotifier<NotificationInboxController> {
  const NotificationInboxScope({
    super.key,
    required NotificationInboxController controller,
    required super.child,
  }) : super(notifier: controller);

  static NotificationInboxController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NotificationInboxScope>()
        ?.notifier;
  }
}

/// Bell that opens a top-right dropdown panel (not a full page).
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({
    super.key,
    this.controller,
    this.color,
    this.alignBelow = false,
  });

  final NotificationInboxController? controller;
  final Color? color;
  /// When true, the panel sits under the bell instead of over the status bar.
  final bool alignBelow;

  Future<void> _openPanel(BuildContext context, NotificationInboxController c) async {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(380.0, size.width - 32);
    final height = math.min(480.0, size.height * 0.62);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero);
    final buttonH = box?.size.height ?? 48;
    final top = alignBelow && origin != null
        ? origin.dy + buttonH + 10
        : MediaQuery.paddingOf(context).top + 8;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notifications',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, anim, _) {
        return Stack(
          children: [
            Positioned(
              top: top,
              right: 16,
              child: FadeTransition(
                opacity: anim,
                child: Material(
                  elevation: 16,
                  color: Theme.of(ctx).colorScheme.surface,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: NotificationsInboxPanel(
                      onChanged: c.refreshUnread,
                      onClose: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    await c.refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller ?? NotificationInboxScope.maybeOf(context);
    if (c == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final count = c.unread;
        return IconButton(
          tooltip: 'Notifications',
          color: color,
          onPressed: () => _openPanel(context, c),
          icon: HeaderCountIcon(
            count: count,
            child: Icon(Icons.notifications_outlined, color: color),
          ),
        );
      },
    );
  }
}

/// Inbox list used inside the bell dropdown.
class NotificationsInboxPanel extends StatefulWidget {
  const NotificationsInboxPanel({
    super.key,
    this.onChanged,
    this.onClose,
  });

  final Future<void> Function()? onChanged;
  final VoidCallback? onClose;

  @override
  State<NotificationsInboxPanel> createState() =>
      _NotificationsInboxPanelState();
}

class _NotificationsInboxPanelState extends State<NotificationsInboxPanel> {
  final _repo = NotificationRepository();
  late Future<List<AppNotification>> _future = _repo.fetchMine();

  Future<void> _reload() async {
    setState(() => _future = _repo.fetchMine());
    await _future;
    await widget.onChanged?.call();
  }

  Future<void> _markAll() async {
    await _repo.markAllRead();
    await _reload();
  }

  Future<void> _open(AppNotification n) async {
    if (n.isUnread) {
      await _repo.markRead(n.id);
      await widget.onChanged?.call();
      if (mounted) setState(() => _future = _repo.fetchMine());
    }
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'rental_approved' => Icons.check_circle_outline,
      'rental_rejected' => Icons.cancel_outlined,
      'rental_ended' => Icons.receipt_long_outlined,
      'rental_request' => Icons.inbox_outlined,
      'kyc_pending' => Icons.badge_outlined,
      'kyc_verified' => Icons.verified_outlined,
      'kyc_rejected' => Icons.gpp_bad_outlined,
      'rental_five_min' => Icons.timer_outlined,
      'rental_overtime' => Icons.warning_amber_rounded,
      'rider_offline' => Icons.signal_wifi_off_rounded,
      'rider_logout_active' => Icons.logout_rounded,
      _ => Icons.notifications_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final df = DateFormat('MMM d, h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Notifications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _markAll,
                child: const Text('Mark all read'),
              ),
              IconButton(
                tooltip: 'Notification settings',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final nav = Navigator.of(context, rootNavigator: true);
                  nav.pop();
                  nav.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NotificationSettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.settings_rounded),
              ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<AppNotification>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${snap.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return const Center(child: Text('No notifications yet.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = rows[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: n.isUnread
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      child: Icon(
                        _iconFor(n.type),
                        size: 18,
                        color: n.isUnread
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      n.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            n.isUnread ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          df.format(n.createdAt.toLocal()),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => _open(n),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

const _countRed = Color(0xFFE53935);

/// Red count that stays inside the header instead of drawing outside it.
class HeaderCountBadge extends StatelessWidget {
  const HeaderCountBadge(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 4 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _countRed,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

class HeaderCountLabel extends StatelessWidget {
  const HeaderCountLabel(this.label, this.count, {super.key});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(8, count > 0 ? 6 : 0, count > 0 ? 14 : 8, 0),
          child: Text(label),
        ),
        if (count > 0)
          Positioned(
            top: 0,
            right: 0,
            child: HeaderCountBadge(count),
          ),
      ],
    );
  }
}

class HeaderCountIcon extends StatelessWidget {
  const HeaderCountIcon({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          if (count > 0)
            Positioned(
              top: 0,
              right: 0,
              child: HeaderCountBadge(count),
            ),
        ],
      ),
    );
  }
}
