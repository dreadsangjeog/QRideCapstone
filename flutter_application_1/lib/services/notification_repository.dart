import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.userId,
    required this.roleScope,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String userId;
  final String roleScope;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      roleScope: (json['role_scope'] as String?) ?? 'user',
      type: (json['type'] as String?) ?? 'unknown',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      data: (json['data'] as Map<String, dynamic>?) ?? const {},
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      readAt: json['read_at'] == null
          ? null
          : DateTime.tryParse(json['read_at'].toString()),
    );
  }
}

class NotificationRepository {
  Future<List<AppNotification>> fetchMine({int limit = 80}) async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await SupabaseClientProvider.client
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List<dynamic>)
        .map((r) => AppNotification.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<int> unreadCount() async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return 0;
    final rows = await SupabaseClientProvider.client
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .isFilter('read_at', null);
    return (rows as List<dynamic>).length;
  }

  Future<void> markRead(String id) async {
    await SupabaseClientProvider.client.from('notifications').update({
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> markAllRead() async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return;
    await SupabaseClientProvider.client.from('notifications').update({
      'read_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('user_id', uid).isFilter('read_at', null);
  }

  /// Client-side history row for timer warnings (also shows in inbox).
  Future<void> insertMine({
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return;
    await SupabaseClientProvider.client.from('notifications').insert({
      'user_id': uid,
      'role_scope': 'user',
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
    });
  }

  /// Inbox row for every admin account (server RPC).
  Future<void> notifyAdmins({
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    await SupabaseClientProvider.client.rpc(
      'notify_all_admins',
      params: {
        'p_type': type,
        'p_title': title,
        'p_body': body,
        'p_data': data ?? {},
      },
    );
  }

  RealtimeChannel subscribeMine({
    required void Function(AppNotification n) onInsert,
  }) {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    final channel = SupabaseClientProvider.client
        .channel('notifications-inbox-${uid ?? 'anon'}');
    if (uid == null) return channel.subscribe();

    return channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            try {
              onInsert(AppNotification.fromJson(payload.newRecord));
            } catch (_) {}
          },
        )
        .subscribe();
  }
}
