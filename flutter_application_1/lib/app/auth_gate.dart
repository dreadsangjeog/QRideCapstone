import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/kyc/kyc_gate.dart';
import '../screens/login_screen.dart';
import '../screens/user_root_shell.dart';
import '../services/auth_service.dart';

/// Routes home by sign-in state and role.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _isAdmin;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _resolveRole();
    _authSub = AuthService.onAuthStateChange.listen((_) => _resolveRole());
  }

  Future<void> _resolveRole() async {
    if (!AuthService.isSignedIn) {
      if (mounted) setState(() => _isAdmin = null);
      return;
    }
    final admin = await AuthService.isAdmin();
    if (mounted) setState(() => _isAdmin = admin);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isSignedIn) return const LoginScreen();
    if (_isAdmin == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _isAdmin!
        ? const AdminDashboardScreen()
        : kIsWeb
            ? const _RiderWebBlocked()
            : const KycGate(child: UserRootShell());
  }
}

class _RiderWebBlocked extends StatelessWidget {
  const _RiderWebBlocked();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QRide Admin'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: AuthService.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'This website is for administrators only.\nRiders should use the QRide Android app to register, verify ID, and rent bikes.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
