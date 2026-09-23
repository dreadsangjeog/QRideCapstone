import 'package:flutter/material.dart';

import 'brand.dart';

/// Brand seed used for light/dark [ColorScheme.fromSeed].
const Color kQrideSeedColor = QrideBrand.seed;

/// Blue light scheme — avoids Material 3's purple shift from [fromSeed].
ColorScheme qrideLightScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: QrideBrand.accent,
    brightness: Brightness.light,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return base.copyWith(
    primary: QrideBrand.accent,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD6EBFF),
    onPrimaryContainer: const Color(0xFF001B3D),
    secondary: QrideBrand.accentDeep,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFE3F1FF),
    onSecondaryContainer: const Color(0xFF00264D),
    tertiary: QrideBrand.accentSoft,
    onTertiary: const Color(0xFF001B3D),
    tertiaryContainer: const Color(0xFFD6EBFF),
    surface: Colors.white,
    onSurface: const Color(0xFF111827),
    surfaceContainerHighest: const Color(0xFFE8F1FA),
    outline: const Color(0xFFC5D4E4),
    outlineVariant: const Color(0xFFD7E3EF),
  );
}

/// Navy / blue dark scheme — no purple containers.
ColorScheme qrideDarkScheme() {
  final base = ColorScheme.fromSeed(
    seedColor: QrideBrand.accent,
    brightness: Brightness.dark,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return base.copyWith(
    primary: const Color(0xFF4DA3FF),
    onPrimary: const Color(0xFF001529),
    primaryContainer: const Color(0xFF0A3D73),
    onPrimaryContainer: const Color(0xFFD7ECFF),
    secondary: QrideBrand.accentSoft,
    onSecondary: const Color(0xFF001529),
    secondaryContainer: const Color(0xFF12324F),
    onSecondaryContainer: const Color(0xFFD7ECFF),
    tertiary: const Color(0xFF7EB6FF),
    onTertiary: const Color(0xFF001529),
    tertiaryContainer: const Color(0xFF163A5C),
    surface: QrideBrand.night,
    onSurface: const Color(0xFFE8EEF6),
    surfaceContainerHighest: const Color(0xFF1A2433),
    outline: const Color(0xFF3D4F66),
    outlineVariant: const Color(0xFF2A384C),
    error: const Color(0xFFFF8A80),
    onError: const Color(0xFF3B0000),
  );
}

ThemeData qrideTheme(ColorScheme cs) => ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      applyElevationOverlayColor: false,
      scaffoldBackgroundColor: cs.brightness == Brightness.light
          ? QrideBrand.mist
          : QrideBrand.night,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.brightness == Brightness.light
            ? QrideBrand.mist
            : QrideBrand.night,
        foregroundColor: cs.onSurface,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: cs.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 24,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          minimumSize: const Size(0, 52),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          minimumSize: const Size(0, 52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: cs.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          minimumSize: const Size(0, 52),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor: cs.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
