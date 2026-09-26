import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/kyc_repository.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_client.dart';
import '../../theme/brand.dart';
import '../../widgets/user_portal_chrome.dart';
import 'kyc_scope.dart';

/// Loads KYC status, then lets the rider into the app.
/// Features stay locked until staff verify.
class KycGate extends StatefulWidget {
  const KycGate({super.key, required this.child});

  final Widget child;

  @override
  State<KycGate> createState() => _KycGateState();
}

class _KycGateState extends State<KycGate> {
  final _repo = KycRepository();
  KycProfile? _profile;
  String? _error;
  RealtimeChannel? _channel;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    unawaited(_channel?.unsubscribe() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.fetchMine();
      if (!mounted) return;
      final becameVerified =
          _lastStatus != null && _lastStatus != 'verified' && p.isVerified;
      _lastStatus = p.status;
      setState(() {
        _profile = p;
        _error = null;
      });
      _listen();
      if (becameVerified) {
        unawaited(NotificationService.playKycVerifiedCue());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _listen() {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null || _channel != null) return;
    _channel = SupabaseClientProvider.client
        .channel('kyc-me-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (_) => unawaited(_load()),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (_error != null && p == null) {
      return Scaffold(
        backgroundColor: QrideBrand.mist,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: PolishedSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return KycScope(
      profile: p,
      reload: _load,
      child: widget.child,
    );
  }
}
