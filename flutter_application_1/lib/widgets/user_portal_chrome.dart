import 'dart:ui';

import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import 'login_scene_backdrop.dart';
import 'qride_brand.dart';
import 'qride_glass.dart';

/// Soft gradient for user-area tabs — same family as splash / launcher.
class UserPortalBackdrop extends StatelessWidget {
  const UserPortalBackdrop({super.key, required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return const QrideBrandBackdrop();
  }
}

/// Lets inner rider pages return to the home map or switch pages.
class RiderNavScope extends InheritedWidget {
  const RiderNavScope({
    super.key,
    required this.goHome,
    required this.openPage,
    required super.child,
  });

  final VoidCallback goHome;
  final ValueChanged<int> openPage;

  static RiderNavScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RiderNavScope>();
  }

  @override
  bool updateShouldNotify(RiderNavScope old) =>
      goHome != old.goHome || openPage != old.openPage;
}

/// Frosted circle used on the map and as a back control.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.foreground = const Color(0xFF111827),
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.48);
    final fg = isDark ? const Color(0xFFE8EEF6) : foreground;
    final rim = Colors.white.withValues(alpha: isDark ? 0.18 : 0.78);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: bg,
            shape: CircleBorder(side: BorderSide(color: rim)),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onTap,
              icon: Icon(icon, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard shell for Scan / Active / History / Profile.
class UserPortalScaffold extends StatelessWidget {
  const UserPortalScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.showBell = true,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool showBell;

  @override
  Widget build(BuildContext context) {
    final home = RiderNavScope.maybeOf(context)?.goHome;
    return AdminGlassScene(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          flexibleSpace: const GlassAppBarBackdrop(),
          leading: (home == null && !Navigator.of(context).canPop())
              ? null
              : IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                      return;
                    }
                    home?.call();
                  },
                ),
          actions: [
            ...?actions,
            if (showBell) const NotificationBellButton(),
          ],
        ),
        body: withGlassHeaderShadow(body),
      ),
    );
  }
}

/// Frosted list group: matches scan / profile cards.
class PolishedSectionCard extends StatelessWidget {
  const PolishedSectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 24,
      padding: EdgeInsets.zero,
      child: child,
    );
  }
}

/// Section label above grouped content.
class PortalSectionLabel extends StatelessWidget {
  const PortalSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
