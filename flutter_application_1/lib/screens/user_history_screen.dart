import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/rental_history_row.dart';
import '../services/rental_repository.dart';
import '../utils/peso.dart';
import '../widgets/user_portal_chrome.dart';

part 'user_history_widgets.dart';

class UserHistoryScreen extends StatefulWidget {
  const UserHistoryScreen({super.key});

  @override
  State<UserHistoryScreen> createState() => _UserHistoryScreenState();
}

class _UserHistoryScreenState extends State<UserHistoryScreen> {
  final _repo = RentalRepository();
  late Future<List<RentalHistoryRow>> _future = _load();
  int? _navIndex;

  Future<List<RentalHistoryRow>> _load() => _repo.fetchMyRentalHistory();

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final index = RiderNavScope.maybeOf(context)?.currentIndex;
    if (index == _navIndex) return;
    final opened = index == 2 && _navIndex != null;
    _navIndex = index;
    if (opened) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _future = _load());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return UserPortalScaffold(
      title: 'History',
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RentalHistoryRow>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(
                error: snapshot.error,
                onRetry: _refresh,
              );
            }
            final items = snapshot.data ?? [];
            if (items.isEmpty) {
              return _EmptyView(onRefresh: _refresh);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: items.length,
              separatorBuilder: (context, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _HistoryCard(item: items[i]),
            );
          },
        ),
      ),
    );
  }
}
