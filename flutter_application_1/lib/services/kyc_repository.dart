import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

class KycProfile {
  KycProfile({
    required this.status,
    this.idImagePath,
    this.selfieImagePath,
    this.note,
  });

  final String status;
  final String? idImagePath;
  final String? selfieImagePath;
  final String? note;

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get needsAction => status == 'unverified' || status == 'rejected';
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
  });

  final String id;
  final String username;
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
            'verification_status, id_image_path, selfie_image_path, verification_note',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return KycProfile(status: 'unverified');
      return KycProfile(
        status: (row['verification_status'] as String?) ?? 'unverified',
        idImagePath: row['id_image_path'] as String?,
        selfieImagePath: row['selfie_image_path'] as String?,
        note: row['verification_note'] as String?,
      );
    } catch (e) {
      final s = e.toString();
      if (s.contains('verification_status') || s.contains('42703')) {
        return KycProfile(status: 'verified');
      }
      rethrow;
    }
  }

  Future<void> submit({
    required Uint8List idBytes,
    required Uint8List selfieFrontBytes,
    required Uint8List selfieLeftBytes,
    required Uint8List selfieRightBytes,
  }) async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) throw StateError('Not signed in');

    final idPath = '$uid/id.jpg';
    final selfiePath = '$uid/selfie.jpg';
    final leftPath = '$uid/selfie_left.jpg';
    final rightPath = '$uid/selfie_right.jpg';
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
    await put(leftPath, selfieLeftBytes);
    await put(rightPath, selfieRightBytes);

    final payload = {
      'id_image_path': idPath,
      'selfie_image_path': selfiePath,
      'selfie_left_image_path': leftPath,
      'selfie_right_image_path': rightPath,
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

  Future<List<KycPendingUser>> searchUsers({
    String query = '',
    String? status,
  }) async {
    final q = query.trim();

    Future<List<dynamic>> run({required bool withSideSelfies}) async {
      final cols = withSideSelfies
          ? 'id, username, role, verification_status, id_image_path, selfie_image_path, selfie_left_image_path, selfie_right_image_path, verification_note'
          : 'id, username, role, verification_status, id_image_path, selfie_image_path, verification_note';
      var filter =
          SupabaseClientProvider.client.from('profiles').select(cols);
      if (status != null && status.isNotEmpty) {
        filter = filter.eq('verification_status', status);
      }
      if (q.isNotEmpty) {
        filter = filter.ilike('username', '%$q%');
      }
      return await filter.order('username').limit(100);
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
        rows = await filter.order('username').limit(100);
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
            status: (m['verification_status'] as String?) ?? 'unverified',
            idImagePath: m['id_image_path'] as String?,
            selfieImagePath: m['selfie_image_path'] as String?,
            selfieLeftPath: m['selfie_left_image_path'] as String?,
            selfieRightPath: m['selfie_right_image_path'] as String?,
            note: m['verification_note'] as String?,
          );
        })
        .whereType<KycPendingUser>()
        .toList();
  }

  Future<List<KycPendingUser>> fetchForAdmin() async {
    return searchUsers(status: 'pending');
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
