import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeMode = 'qride_theme_mode';

/// Global theme-mode notifier. Toggle dark/light from anywhere in the app.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadSavedThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value = switch (prefs.getString(_kThemeMode)) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
}

void setThemeMode(ThemeMode mode) {
  themeNotifier.value = mode;
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString(
      _kThemeMode,
      switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      },
    );
  });
}
