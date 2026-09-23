import 'package:flutter/material.dart';

/// Light QRide UI brand — bright blue on airy backgrounds.
/// Launcher bike icon stays as-is; chrome uses this lighter palette.
abstract final class QrideBrand {
  /// Dark plate behind the bike mark (matches app icon).
  static const Color ink = Color(0xFF0A0A0A);

  static const Color accent = Color(0xFF007AFF);
  static const Color accentDeep = Color(0xFF0A5FCF);
  static const Color accentSoft = Color(0xFF64B5F6);
  static const Color mist = Color(0xFFF4F8FC);
  static const Color night = Color(0xFF0B1220);

  static const String logoMark = 'assets/images/qride_logo_mark.png';
  static const String appIcon = 'assets/images/qride_app_icon.png';
  /// Transparent blue bike for light auth / home chrome.
  static const String bikeLight = 'assets/images/qride_bike_light.png';

  static const Color seed = accent;

  // Back-compat aliases used by older screens.
  static const Color plum = accentDeep;
  static const Color plumBright = accent;
  static const Color plumSoft = accentSoft;
}
