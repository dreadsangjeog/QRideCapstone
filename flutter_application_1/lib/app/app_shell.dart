import 'package:flutter/material.dart';

import '../screens/splash_screen.dart';
import 'auth_gate.dart';

/// Shows splash on cold start, then [AuthGate].
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _splashDone
          ? const AuthGate(key: ValueKey('auth-gate'))
          : SplashScreen(
              key: const ValueKey('splash'),
              onFinished: () {
                if (mounted) setState(() => _splashDone = true);
              },
            ),
    );
  }
}
