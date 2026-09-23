import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bike.dart';
import '../../models/rental.dart';
import '../../models/rental_location.dart';
import '../../models/rental_with_bike.dart';
import 'admin_generate_qr_screen.dart';
import 'admin_history_tab.dart';
import 'admin_home_tab.dart';
import 'admin_map_tab.dart';
import 'admin_requests_tab.dart';
import 'admin_verify_users_tab.dart';
import '../../services/admin_repository.dart';
import '../../services/analytics_repository.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_client.dart';
import '../notifications_screen.dart';

part 'admin_dashboard_widgets.dart';
part 'admin_dashboard_tabs.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  static const routeName = '/admin';

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminRepository();
  final _inbox = NotificationInboxController();
  final _requestsTabKey = GlobalKey<AdminRequestsTabState>();
  RealtimeChannel? _pendingChannel;
  bool _adminGatePassed = false;
  int _pendingRequestCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAdmin());
  }

  @override
  void dispose() {
    _pendingChannel?.unsubscribe();
    _inbox.dispose();
    super.dispose();
  }

  Future<void> _ensureAdmin() async {
    final ok = await AuthService.isAdmin();
    if (!mounted) return;
    if (!ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Access denied'),
          content: const Text(
            'The admin dashboard is only available to accounts with the administrator role in QRide.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _adminGatePassed = true;
      _inbox.start();
    });
    unawaited(_refreshPendingCount());
    _subscribePendingCount();
  }

  Future<void> _refreshPendingCount() async {
    try {
      final count = await _repo.countPendingRentals();
      if (!mounted) return;
      setState(() => _pendingRequestCount = count);
    } catch (e) {
      debugPrint('pending request count failed: $e');
    }
  }

  void _subscribePendingCount() {
    _pendingChannel?.unsubscribe();
    _pendingChannel = SupabaseClientProvider.client
        .channel('admin-pending-request-count')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rentals',
          callback: (_) {
            unawaited(_refreshPendingCount());
            unawaited(_requestsTabKey.currentState?.refresh());
          },
        )
        .subscribe();
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.logout_rounded, color: cs.error, size: 28),
        title: const Text('Log out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    const adminHeaderBlue = Color(0xFF007AFF);

    if (!_adminGatePassed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'QRide Admin',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          automaticallyImplyLeading: false,
          backgroundColor: adminHeaderBlue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 8,
      initialIndex: 0,
      child: Builder(
        builder: (context) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'QRide Admin',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          automaticallyImplyLeading: false,
          backgroundColor: adminHeaderBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            NotificationBellButton(controller: _inbox, color: Colors.white),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Log out',
              onPressed: () => _confirmLogout(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            tabs: [
              const Tab(
                text: 'Dashboard',
                icon: Icon(Icons.space_dashboard_outlined),
              ),
              const Tab(
                text: 'Bikes',
                icon: Icon(Icons.directions_bike_outlined),
              ),
              Tab(
                text: 'Requests',
                icon: Badge(
                  isLabelVisible: _pendingRequestCount > 0,
                  backgroundColor: const Color(0xFFE53935),
                  textColor: Colors.white,
                  label: Text(
                    _pendingRequestCount > 99
                        ? '99+'
                        : '$_pendingRequestCount',
                  ),
                  child: const Icon(Icons.inbox_outlined),
                ),
              ),
              const Tab(
                text: 'Active',
                icon: Icon(Icons.play_circle_outline),
              ),
              const Tab(
                text: 'History',
                icon: Icon(Icons.history_rounded),
              ),
              const Tab(
                text: 'Map',
                icon: Icon(Icons.map_outlined),
              ),
              const Tab(
                text: 'Users',
                icon: Icon(Icons.badge_outlined),
              ),
              const Tab(
                text: 'Reports',
                icon: Icon(Icons.insights_outlined),
              ),
            ],
          ),
        ),
        body: TabBarView(
          physics: kIsWeb ? const NeverScrollableScrollPhysics() : null,
          children: [
            AdminHomeTab(
              repo: _repo,
              pendingCount: _pendingRequestCount,
              onOpenTab: (i) => DefaultTabController.of(context).animateTo(i),
            ),
            _BikesTab(repo: _repo),
            AdminRequestsTab(
              key: _requestsTabKey,
              repo: _repo,
              onQueueChanged: _refreshPendingCount,
            ),
            _ActiveRentalsTab(repo: _repo),
            AdminHistoryTab(repo: _repo),
            AdminMapTab(repo: _repo),
            const AdminVerifyUsersTab(),
            _ReportsTab(repo: AnalyticsRepository()),
          ],
        ),
      ),
      ),
    );
  }
}
