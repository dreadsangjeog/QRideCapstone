import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

class KycProfile {
  KycProfile({
    required this.status,
    this.idImagePath,
    this.selfieImagePath,
    this.note,
    this.firstName,
    this.middleName,
    this.lastName,
    this.birthdate,
  });

  final String status;
  final String? idImagePath;
  final String? selfieImagePath;
  final String? note;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? birthdate;

  String get legalName {
    final parts = [firstName, middleName, lastName]
        .map((s) => (s ?? '').trim())
        .where((s) => s.isNotEmpty);
    return parts.join(' ');
  }

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get needsAction => status == 'unverified' || status == 'rejected';

  /// Name and birthdate freeze after the AI ID check.
  bool get personalDetailsLocked => status != 'unverified';
}

class KycPendingUser {
  KycPendingUser({
    required this.id,
    required this.username,
    required this.status,
    this.idImagePath,
    this.selfieImagePath,
    this.selfieLeftPath,
    this.selfieRightPath,
    this.note,
    this.firstName,
    this.middleName,
    this.lastName,
    this.createdAt,
  });

  final String id;
  final String username;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final DateTime? createdAt;

  String get legalName {
    final parts = [firstName, middleName, lastName]
        .map((s) => (s ?? '').trim())
        .where((s) => s.isNotEmpty);
    return parts.join(' ');
  }

  /// Legal name when it is on file, otherwise the login username.
  String get displayName {
    final name = legalName.trim();
    return name.isEmpty ? username : name;
  }

  final String status;
  final String? idImagePath;
  final String? selfieImagePath;
  final String? selfieLeftPath;
  final String? selfieRightPath;
  final String? note;
}

class KycRepository {
  static const bucket = 'kyc-documents';

  Future<KycProfile> fetchMine() async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) {
      return KycProfile(status: 'unverified');
    }
    try {
      final row = await SupabaseClientProvider.client
          .from('profiles')
          .select(
            'verification_status, id_image_path, selfie_image_path, verification_note, first_name, middle_name, last_name, birthdate',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return KycProfile(status: 'unverified');
      return _profileFromRow(row);
    } catch (e) {
      final s = e.toString();
      if (s.contains('first_name') || s.contains('42703')) {
        return _fetchMineWithoutName();
      }
      if (s.contains('verification_status')) {
        return KycProfile(status: 'verified');
      }
      rethrow;
    }
  }

  Future<KycProfile> _fetchMineWithoutName() async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return KycProfile(status: 'unverified');
    try {
      final row = await SupabaseClientProvider.client
          .from('profiles')
          .select(
            'verification_status, id_image_path, selfie_image_path, verification_note',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return KycProfile(status: 'unverified');
      return _profileFromRow(row);
    } catch (_) {
      return KycProfile(status: 'verified');
    }
  }

  KycProfile _profileFromRow(Map<String, dynamic> row) => KycProfile(
        status: (row['verification_status'] as String?) ?? 'unverified',
        idImagePath: row['id_image_path'] as String?,
        selfieImagePath: row['selfie_image_path'] as String?,
        note: row['verification_note'] as String?,
        firstName: row['first_name'] as String?,
        middleName: row['middle_name'] as String?,
        lastName: row['last_name'] as String?,
        birthdate: row['birthdate']?.toString(),
      );

  /// Saves the name used to match the uploaded ID. No-op once verified.
  Future<void> updateLegalName({
    required String firstName,
    String? middleName,
    required String lastName,
    String? birthdate,
  }) async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    final current = await fetchMine();
    if (current.personalDetailsLocked) {
      throw StateError(
        'Your name and birthdate are locked after the ID check.',
      );
    }
    await SupabaseClientProvider.client.from('profiles').update({
      'first_name': firstName.trim(),
      'middle_name': (middleName ?? '').trim().isEmpty
          ? null
          : middleName!.trim(),
      'last_name': lastName.trim(),
      if ((birthdate ?? '').trim().isNotEmpty) 'birthdate': birthdate!.trim(),
    }).eq('id', uid);
  }

  Future<void> submit({
    required Uint8List idBytes,
    required Uint8List selfieFrontBytes,
  }) async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    final idPath = '$uid/id.jpg';
    final selfiePath = '$uid/selfie.jpg';
    final storage = SupabaseClientProvider.client.storage.from(bucket);

    Future<void> put(String path, Uint8List bytes) {
      return storage.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
        ),
      );
    }

    await put(idPath, idBytes);
    await put(selfiePath, selfieFrontBytes);

    final payload = {
      'id_image_path': idPath,
      'selfie_image_path': selfiePath,
      'liveness_passed_at': DateTime.now().toUtc().toIso8601String(),
      'verification_status': 'pending',
      'verification_note': null,
    };

    try {
      await SupabaseClientProvider.client
          .from('profiles')
          .update(payload)
          .eq('id', uid);
    } catch (e) {
      final s = e.toString();
      if (!s.contains('selfie_left_image_path') &&
          !s.contains('selfie_right_image_path') &&
          !s.contains('42703')) {
        rethrow;
      }
      payload.remove('selfie_left_image_path');
      payload.remove('selfie_right_image_path');
      await SupabaseClientProvider.client
          .from('profiles')
          .update(payload)
          .eq('id', uid);
    }
  }

  /// AI passed. Stay pending so staff make the final decision.
  Future<void> holdForStaffReview({required String note}) async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');
    await SupabaseClientProvider.client.from('profiles').update({
      'verification_status': 'pending',
      'verification_note': note.trim().isEmpty
          ? 'Name and face passed the app check. Waiting for staff to verify.'
          : note.trim(),
    }).eq('id', uid);
  }

  Future<String> applyAutoReview({
    required bool nameMatch,
    required bool photoMatch,
    required String note,
  }) async {
    final raw = await SupabaseClientProvider.client.rpc(
      'kyc_apply_auto_review',
      params: {
        'p_name_ok': nameMatch,
        'p_photo_ok': photoMatch,
        'p_note': note,
      },
    );
    return raw?.toString() ?? 'rejected';
  }

  Future<List<KycPendingUser>> searchUsers({
    String query = '',
    String? status,
  }) async {
    final q = query.trim();

    Future<List<dynamic>> run({required bool withSideSelfies}) async {
      final cols = withSideSelfies
          ? 'id, username, role, verification_status, id_image_path, selfie_image_path, selfie_left_image_path, selfie_right_image_path, verification_note, first_name, middle_name, last_name, created_at'
          : 'id, username, role, verification_status, id_image_path, selfie_image_path, verification_note, created_at';
      var filter =
          SupabaseClientProvider.client.from('profiles').select(cols);
      if (status != null && status.isNotEmpty) {
        filter = filter.eq('verification_status', status);
      }
      if (q.isNotEmpty) {
        final safe = q.replaceAll(RegExp(r'[%*,()]'), '');
        if (safe.isNotEmpty) {
          filter = withSideSelfies
              ? filter.or(
                  'username.ilike.%$safe%,first_name.ilike.%$safe%,middle_name.ilike.%$safe%,last_name.ilike.%$safe%',
                )
              : filter.ilike('username', '%$safe%');
        }
      }
      return await filter.order('username', ascending: true).limit(100);
    }

    List<dynamic> rows;
    try {
      rows = await run(withSideSelfies: true);
    } catch (_) {
      try {
        rows = await run(withSideSelfies: false);
      } catch (_) {
        // Older schemas without role column.
        var filter = SupabaseClientProvider.client.from('profiles').select(
              'id, username, verification_status, id_image_path, selfie_image_path, verification_note',
            );
        if (status != null && status.isNotEmpty) {
          filter = filter.eq('verification_status', status);
        }
        if (q.isNotEmpty) {
          filter = filter.ilike('username', '%$q%');
        }
        rows = await filter.order('username', ascending: true).limit(100);
      }
    }

    return rows
        .map((raw) {
          final m = raw as Map<String, dynamic>;
          if ((m['role'] as String?) == 'admin') return null;
          final id = m['id'].toString();
          return KycPendingUser(
            id: id,
            username: (m['username'] as String?) ?? 'user',
            firstName: m['first_name'] as String?,
            middleName: m['middle_name'] as String?,
            lastName: m['last_name'] as String?,
            status: (m['verification_status'] as String?) ?? 'unverified',
            idImagePath: m['id_image_path'] as String?,
            selfieImagePath: m['selfie_image_path'] as String?,
            selfieLeftPath: m['selfie_left_image_path'] as String?,
            selfieRightPath: m['selfie_right_image_path'] as String?,
            note: m['verification_note'] as String?,
            createdAt: DateTime.tryParse(m['created_at']?.toString() ?? ''),
          );
        })
        .whereType<KycPendingUser>()
        .toList()
      ..sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );
  }

  Future<List<KycPendingUser>> fetchForAdmin() async {
    return searchUsers(status: 'pending');
  }

  /// Riders waiting for an ID review. Admins are excluded.
  Future<int> countPendingReviews() async {
    final rows = await SupabaseClientProvider.client
        .from('profiles')
        .select('id')
        .eq('verification_status', 'pending')
        .neq('role', 'admin');
    return (rows as List<dynamic>).length;
  }

  Future<String> signedUrl(String path) async {
    return SupabaseClientProvider.client.storage
        .from(bucket)
        .createSignedUrl(path, 3600);
  }

  Future<String?> signedUrlOrNull(String path) async {
    try {
      return await signedUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> setStatus({
    required String userId,
    required String status,
    String? note,
  }) async {
    await SupabaseClientProvider.client.from('profiles').update({
      'verification_status': status,
      'verification_note': note,
      'verified_at': status == 'verified'
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    }).eq('id', userId);
  }
}
