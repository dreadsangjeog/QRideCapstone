import 'package:flutter/material.dart';

import 'qride_brand.dart';

/// Login / marketing gradient behind [SafeArea] content.
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return QrideBrandBackdrop(child: child);
  }
}

/// Bike mark, “QRide” wordmark and the Scan · Ride · Return tagline.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 12),
        QrideBikeMark(size: 88),
        SizedBox(height: 16),
        QrideWordmark(fontSize: 36),
        SizedBox(height: 6),
        QrideTagline(),
        SizedBox(height: 28),
      ],
    );
  }
}
