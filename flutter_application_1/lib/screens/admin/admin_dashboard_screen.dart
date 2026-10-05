import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/bike.dart';
import '../../models/rental.dart';
import '../../models/rental_location.dart';
import '../../models/rental_with_bike.dart';
import '../../widgets/login_scene_backdrop.dart';
import '../../widgets/qride_brand.dart';
import '../../widgets/qride_glass.dart';
import 'admin_generate_qr_screen.dart';
import 'admin_hourly_rate_card.dart';
import 'admin_history_tab.dart';
import 'admin_home_tab.dart';
import 'admin_layout.dart';
import 'admin_map_tab.dart';
import 'admin_reports_tab.dart';
import 'admin_requests_tab.dart';
import 'admin_verify_users_tab.dart';
import '../../services/admin_repository.dart';
import '../../utils/admin_sort.dart';
import '../../services/rental_repository.dart';
import '../../services/kyc_repository.dart';
import '../../services/analytics_repository.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_client.dart';
import '../../theme/brand.dart';
import '../../utils/peso.dart';
import '../../utils/rental_billing.dart';
import '../../widgets/bike_photo.dart';
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
  final _kyc = KycRepository();
  final _inbox = NotificationInboxController();
  final _requestsTabKey = GlobalKey<AdminRequestsTabState>();
  RealtimeChannel? _pendingChannel;
  bool _adminGatePassed = false;
  int _pendingRequestCount = 0;
  int _pendingUserCount = 0;
  int _activeRentalCount = 0;
  final _liveTick = ValueNotifier<int>(0);
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureAdmin());
  }

  @override
  void dispose() {
    _pendingChannel?.unsubscribe();
    _liveDebounce?.cancel();
    _liveTick.dispose();
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

  void _onLiveData() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _liveTick.value++;
      unawaited(_refreshPendingCount());
      unawaited(_requestsTabKey.currentState?.refresh());
    });
  }

  Future<void> _refreshPendingCount() async {
    try {
      final results = await Future.wait<int>([
        _repo.countPendingRentals(),
        _kyc.countPendingReviews(),
        _repo.countActiveRentals(),
      ]);
      if (!mounted) return;
      setState(() {
        _pendingRequestCount = results[0];
        _pendingUserCount = results[1];
        _activeRentalCount = results[2];
      });
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
          callback: (_) => _onLiveData(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _onLiveData(),
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
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final onBar = isDark ? Colors.white : const Color(0xFF111827);

    if (!_adminGatePassed) {
      return AdminGlassScene(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text(
              'QRide Admin',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            automaticallyImplyLeading: false,
            backgroundColor: Colors.transparent,
            foregroundColor: onBar,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: const GlassAppBarBackdrop(),
          ),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AdminGlassScene(
      child: DefaultTabController(
      length: 8,
      initialIndex: 0,
      child: Builder(
        builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Row(
            children: [
              const QrideBikeMark(size: 34),
              const SizedBox(width: 10),
              const Text(
                'QRide',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.4),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isDark ? cs.primary : QrideBrand.accent)
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Admin',
                  style: TextStyle(
                    color: isDark ? cs.primary : QrideBrand.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          foregroundColor: onBar,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: const GlassAppBarBackdrop(),
          actions: [
            AdminSeasonToggle(color: onBar),
            AdminThemeToggle(color: onBar),
            NotificationBellButton(controller: _inbox, color: onBar),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Log out',
              onPressed: () => _confirmLogout(context),
            ),
            const SizedBox(width: 6),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicator: BoxDecoration(
              color: (isDark ? cs.primary : QrideBrand.accent)
                  .withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: isDark ? cs.primary : QrideBrand.accent,
            unselectedLabelColor: onBar.withValues(alpha: 0.72),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            dividerColor: Colors.transparent,
            tabs: [
              const Tab(text: '  Dashboard  '),
              const Tab(text: '  Bikes  '),
              Tab(child: HeaderCountLabel('Requests', _pendingRequestCount)),
              Tab(child: HeaderCountLabel('Active', _activeRentalCount)),
              const Tab(text: '  History  '),
              const Tab(text: '  Map  '),
              Tab(child: HeaderCountLabel('Users', _pendingUserCount)),
              const Tab(text: '  Reports  '),
            ],
          ),
        ),
        body: withGlassHeaderShadow(TabBarView(
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
            _ActiveRentalsTab(repo: _repo, changes: _liveTick),
            AdminHistoryTab(repo: _repo, changes: _liveTick),
            AdminMapTab(repo: _repo),
            AdminVerifyUsersTab(changes: _liveTick),
            AdminReportsTab(repo: AnalyticsRepository()),
          ],
        )),
      ),
      ),
      ),
    );
  }
}
