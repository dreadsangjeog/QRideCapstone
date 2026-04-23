import 'package:flutter/material.dart';

import 'user_scan_screen.dart';
import 'user_active_rental_screen.dart';
import 'user_history_screen.dart';
import 'user_profile_screen.dart';

class UserRootShell extends StatefulWidget {
  const UserRootShell({super.key});

  static const routeName = '/user';

  @override
  State<UserRootShell> createState() => _UserRootShellState();
}

class _UserRootShellState extends State<UserRootShell> {
  int _currentIndex = 0;

  final _pages = const [
    UserScanScreen(),
    UserActiveRentalScreen(),
    UserHistoryScreen(),
    UserProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          indicatorColor: cs.primaryContainer.withValues(alpha: 0.85),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final base = theme.textTheme.labelMedium;
            if (states.contains(WidgetState.selected)) {
              return base?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              );
            }
            return base?.copyWith(
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: cs.primary, size: 26);
            }
            return IconThemeData(
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              size: 24,
            );
          }),
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black26,
          elevation: 8,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.qr_code_scanner_outlined),
              selectedIcon: Icon(Icons.qr_code_scanner_rounded),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.directions_bike_outlined),
              selectedIcon: Icon(Icons.directions_bike_rounded),
              label: 'Active',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
