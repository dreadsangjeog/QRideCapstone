import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Desktop / web breakpoint for the admin console.
bool adminWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// True when [context] is inside a route opened by [showAdminPage] as a dialog.
bool adminInDialog(BuildContext context) => ModalRoute.of(context) is DialogRoute;

/// Opens [builder] as a centered dialog on wide screens, full screen on phones.
Future<T?> showAdminPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 760,
}) {
  if (!adminWide(context)) {
    return Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: builder));
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SizedBox(
          width: math.min(maxWidth, size.width - 48),
          height: math.min(size.height * 0.9, 920),
          child: builder(ctx),
        ),
      );
    },
  );
}

/// Close button for app bars of pages opened with [showAdminPage].
Widget? adminDialogLeading(BuildContext context, [VoidCallback? onClose]) {
  if (!adminInDialog(context)) return null;
  return IconButton(
    tooltip: 'Close',
    icon: const Icon(Icons.close_rounded),
    onPressed: onClose ?? () => Navigator.of(context).maybePop(),
  );
}

/// Centers tab content with a comfortable max width on large screens.
class AdminContent extends StatelessWidget {
  const AdminContent({super.key, required this.child, this.maxWidth = 1280});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Lays cards out in as many equal columns as fit (single column on phones).
class AdminCardGrid extends StatelessWidget {
  const AdminCardGrid({
    super.key,
    required this.children,
    this.minItemWidth = 360,
    this.spacing = 14,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = math.max(1, ((w + spacing) / (minItemWidth + spacing)).floor());
        final itemW = (w - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final c in children) SizedBox(width: itemW, child: c),
          ],
        );
      },
    );
  }
}

/// Title row used at the top of admin tabs.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Padding used around admin tab bodies.
EdgeInsets adminPagePadding(BuildContext context) => adminWide(context)
    ? const EdgeInsets.fromLTRB(28, 22, 28, 36)
    : const EdgeInsets.fromLTRB(16, 14, 16, 28);

/// Compact A–Z / Newest control that sits on the same row as status filters.
class AdminSortToggle extends StatelessWidget {
  const AdminSortToggle({
    super.key,
    required this.newestFirst,
    required this.onChanged,
  });

  final bool newestFirst;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sort',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segment(context, 'A–Z', !newestFirst, () => onChanged(false)),
                _segment(context, 'Newest', newestFirst, () => onChanged(true)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? cs.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
