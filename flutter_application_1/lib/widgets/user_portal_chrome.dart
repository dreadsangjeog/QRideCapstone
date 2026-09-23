import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../theme/brand.dart';
import 'qride_brand.dart';

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
        ? const Color(0xE6182233)
        : Colors.white.withValues(alpha: 0.96);
    final fg = isDark ? const Color(0xFFE8EEF6) : foreground;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: fg),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final base = isDark ? QrideBrand.night : QrideBrand.mist;
    final home = RiderNavScope.maybeOf(context)?.goHome;
    return Scaffold(
      backgroundColor: base,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        backgroundColor: base.withValues(alpha: 0.88),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: UserPortalBackdrop(colorScheme: cs)),
          body,
        ],
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
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.92),
      elevation: 0,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: child,
        ),
      ),
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
