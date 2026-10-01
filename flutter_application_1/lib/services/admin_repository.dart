import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bike.dart';
import '../models/rental.dart';
import '../models/rental_location.dart';
import '../models/rental_with_bike.dart';
import 'supabase_client.dart';

class AdminRepository {
  Future<List<Bike>> fetchBikes() async {
    List<Bike> parse(dynamic rows) {
      final bikes = (rows as List<dynamic>)
          .map((e) => Bike.fromJson(e as Map<String, dynamic>))
          .toList();
      bikes.sort(
        (a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()),
      );
      return bikes;
    }

    try {
      final rows = await SupabaseClientProvider.client
          .from('bikes')
          .select()
          .order('code', ascending: true);
      return parse(rows);
    } catch (e) {
      final s = e.toString();
      if (!s.contains('photo_path') && !s.contains('42703')) rethrow;
      final rows = await SupabaseClientProvider.client
          .from('bikes')
          .select('id, code, label, status, created_at')
          .order('code', ascending: true);
      return parse(rows);
    }
  }

  /// Proposes a random bike code (`BIKE-` + 6 chars) and checks Supabase until unused.
  ///
  /// Uses [fetchBikeByCode]; characters exclude ambiguous `0`/`O`/`1`/`I`.
  Future<String> generateUniqueBikeCode({int maxAttempts = 48}) async {
    final rnd = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final suffix = List.generate(
        6,
        (_) => chars[rnd.nextInt(chars.length)],
      ).join();
      final code = 'BIKE-$suffix';
      final taken = await fetchBikeByCode(code);
      if (taken == null) return code;
    }
    throw StateError(
      'Could not find a unique bike code after $maxAttempts tries.',
    );
  }

  /// Looks up a bike by its [code] (exact match after trim).
  Future<Bike?> fetchBikeByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final row = await SupabaseClientProvider.client
        .from('bikes')
        .select()
        .eq('code', c)
        .maybeSingle();
    if (row == null) return null;
    return Bike.fromJson(Map<String, dynamic>.from(row));
  }

  Future<void> updateBikeStatus({
    required String bikeId,
    required String status,
  }) async {
    if (status == 'rented') {
      throw Exception(
        'Rented is set automatically when a rider’s rental is approved.',
      );
    }
    await SupabaseClientProvider.client
        .from('bikes')
        .update({'status': status}).eq('id', bikeId);
  }

  /// Inserts a bike row. [code] must be unique. Requires `profiles.role = admin` (RLS).
  Future<Bike> createBike({
    required String code,
    required String label,
    String status = 'available',
  }) async {
    if (status == 'rented') {
      throw Exception(
        'Rented is set automatically when a rider’s rental is approved.',
      );
    }
    final row = await SupabaseClientProvider.client
        .from('bikes')
        .insert({
          'code': code.trim(),
          'label': label.trim(),
          'status': status,
        })
        .select()
        .single();
    return Bike.fromJson(Map<String, dynamic>.from(row));
  }

  /// Saves the hourly fee. Completed rides keep the totals already recorded.
  ///
  /// From this save onward, new requests and the rest of an open ride use
  /// the new fee. That cutoff is stored by migration 037_rate_history.sql.
  Future<double> setHourlyRate(double rate) async {
    if (rate.isNaN || rate <= 0 || rate > 10000) {
      throw StateError('Enter an hourly fee greater than 0 and at most 10000.');
    }
    final rounded = (rate * 100).roundToDouble() / 100;
    try {
      final rows = await SupabaseClientProvider.client
          .from('rental_settings')
          .update({
            'rate_per_hour': rounded,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', 1)
          .select('rate_per_hour');
      if ((rows as List).isEmpty) {
        throw StateError(
          'Hourly fee is not set up yet. Run migration 035_hourly_rate.sql in Supabase.',
        );
      }
      return ((rows.first as Map)['rate_per_hour'] as num).toDouble();
    } catch (e) {
      final s = e.toString();
      if (s.contains('rental_settings') ||
          s.contains('PGRST205') ||
          s.contains('42P01') ||
          s.contains('does not exist')) {
        throw StateError(
          'Hourly fee is not set up yet. Run migration 035_hourly_rate.sql in Supabase.',
        );
      }
      rethrow;
    }
  }

  static const photoBucket = 'bike-photos';

  /// Public URL for a stored bike photo, or null when none.
  static String? publicPhotoUrl(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return null;
    return SupabaseClientProvider.client.storage
        .from(photoBucket)
        .getPublicUrl(p);
  }

  /// Uploads (or replaces) the photo for [bikeId]. Returns the updated bike.
  Future<Bike> uploadBikePhoto({
    required String bikeId,
    required Uint8List bytes,
    String? previousPath,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('Choose a photo first.');
    }
    if (bytes.lengthInBytes > 8 * 1024 * 1024) {
      throw StateError('Use a photo smaller than 8 MB.');
    }
    final path = '$bikeId/photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
    final storage = SupabaseClientProvider.client.storage.from(photoBucket);
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        upsert: true,
        contentType: 'image/jpeg',
      ),
    );
    final row = await SupabaseClientProvider.client
        .from('bikes')
        .update({'photo_path': path})
        .eq('id', bikeId)
        .select()
        .single();
    final old = (previousPath ?? '').trim();
    if (old.isNotEmpty && old != path) {
      try {
        await storage.remove([old]);
      } catch (_) {}
    }
    return Bike.fromJson(Map<String, dynamic>.from(row));
  }

  /// Removes the stored photo for [bikeId].
  Future<Bike> removeBikePhoto({
    required String bikeId,
    String? previousPath,
  }) async {
    final old = (previousPath ?? '').trim();
    if (old.isNotEmpty) {
      try {
        await SupabaseClientProvider.client.storage
            .from(photoBucket)
            .remove([old]);
      } catch (_) {}
    }
    final row = await SupabaseClientProvider.client
        .from('bikes')
        .update({'photo_path': null})
        .eq('id', bikeId)
        .select()
        .single();
    return Bike.fromJson(Map<String, dynamic>.from(row));
  }

  /// Permanently deletes a bike from the fleet.
  ///
  /// Blocked while the bike has a pending or active rental. Ended history is
  /// kept; the bike link on those rows is cleared.
  Future<void> deleteBike(Bike bike) async {
    if (bike.status == 'rented') {
      throw Exception(
        'This bike is rented. End the active rental before deleting it.',
      );
    }
    final path = (bike.photoPath ?? '').trim();
    await SupabaseClientProvider.client.rpc(
      'admin_delete_bike',
      params: {'p_bike_id': bike.id},
    );
    if (path.isNotEmpty) {
      try {
        await SupabaseClientProvider.client.storage
            .from(photoBucket)
            .remove([path]);
      } catch (_) {}
    }
  }

  Future<List<Rental>> fetchActiveRentals() async {
    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select()
        .eq('status', 'active')
        .order('started_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => Rental.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Active rentals with joined bike row (code/label for admin UI).
  Future<List<RentalWithBike>> fetchActiveRentalsWithBikes() async {
    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select(
          '*, bikes(*), profiles(username, first_name, middle_name, last_name)',
        )
        .eq('status', 'active')
        .order('approved_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => RentalWithBike.fromJoinedJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Full rental log for admin (newest first). Optional [status] filters to one status.
  Future<List<RentalWithBike>> fetchRentalsHistory({
    int limit = 500,
    String? status,
  }) async {
    var q = SupabaseClientProvider.client
        .from('rentals')
        .select(
          '*, bikes(*), profiles(username, first_name, middle_name, last_name)',
        );
    if (status != null && status.isNotEmpty) {
      q = q.eq('status', status);
    }
    final rows = await q.order('started_at', ascending: false).limit(limit);
    return (rows as List<dynamic>)
        .map((e) => RentalWithBike.fromJoinedJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Pending rental requests waiting for admin approval.
  Future<List<RentalWithBike>> fetchPendingRentals() async {
    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select(
          '*, bikes(*), profiles(username, first_name, middle_name, last_name)',
        )
        .eq('status', 'pending')
        .order('started_at', ascending: true);
    return (rows as List<dynamic>)
        .map((e) => RentalWithBike.fromJoinedJson(e as Map<String, dynamic>))
        .toList();
  }

  /// How many rentals are currently pending acceptance.
  Future<int> countPendingRentals() async {
    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select('id')
        .eq('status', 'pending');
    return (rows as List<dynamic>).length;
  }

  Future<int> countActiveRentals() async {
    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select('id')
        .eq('status', 'active');
    return (rows as List<dynamic>).length;
  }

  /// Approves a pending rental — the user's countdown starts from this moment.
  Future<void> approveRental(String rentalId) async {
    await SupabaseClientProvider.client.rpc(
      'approve_rental',
      params: {'p_rental_id': rentalId},
    );
  }

  /// Rejects a pending rental — the bike is freed immediately.
  /// Kept for SQL RPC compatibility; admin UI is accept-only.
  Future<void> rejectRental(String rentalId) async {
    await SupabaseClientProvider.client.rpc(
      'reject_rental',
      params: {'p_rental_id': rentalId},
    );
  }

  /// Ends an active rental. Pass pre-calculated [actualCost] and [penaltyFee].
  Future<void> endRentalByAdmin({
    required String rentalId,
    required double actualCost,
    required double penaltyFee,
  }) async {
    await SupabaseClientProvider.client.rpc(
      'end_rental_by_admin',
      params: {
        'p_rental_id': rentalId,
        'p_actual_cost': actualCost,
        'p_penalty_fee': penaltyFee,
      },
    );
  }

  /// Fix billing on an already-ended rental (late end, wrong tap, waived penalty, etc.).
  /// [actualCost] is total charged (base + penalty), matching [endRentalByAdmin].
  Future<void> adjustEndedRentalBilling({
    required String rentalId,
    required double actualCost,
    required double penaltyFee,
  }) async {
    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .update({
          'actual_cost': actualCost,
          'penalty_fee': penaltyFee,
        })
        .eq('id', rentalId)
        .eq('status', 'ended')
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError('Could not update rental (missing or not ended).');
    }
  }

  Future<RentalLocation?> fetchLastLocationForRental(String rentalId) async {
    final row = await SupabaseClientProvider.client
        .from('rental_last_location')
        .select()
        .eq('rental_id', rentalId)
        .maybeSingle();
    if (row == null) return null;
    return RentalLocation.fromJson(row);
  }

  /// Returns last-known GPS locations for all currently active rentals,
  /// with bike info attached. Uses two queries to avoid PostgREST embedded-filter
  /// quirks that can silently return empty results.
  Future<List<Map<String, dynamic>>> fetchActiveRentalLastLocationsJoined() async {
    // Step 1: get IDs of all active rentals plus their bike + rider info.
    final activeRentals = await SupabaseClientProvider.client
        .from('rentals')
        .select(
          'id, bikes(code, label), profiles(username, first_name, middle_name, last_name)',
        )
        .eq('status', 'active');

    if ((activeRentals as List).isEmpty) return [];

    final rentalIds = activeRentals
        .map((r) => r['id'].toString())
        .toList();

    // Step 2: get last locations for those rental IDs.
    final locations = await SupabaseClientProvider.client
        .from('rental_last_location')
        .select()
        .inFilter('rental_id', rentalIds);

    // Merge bike + rider info into each location row.
    final bikeMap = <String, Map<String, dynamic>>{
      for (final r in activeRentals)
        r['id'].toString(): {
          'rentals': {
            'status': 'active',
            'bikes': r['bikes'],
            'profiles': r['profiles'],
          },
        },
    };

    return (locations as List<dynamic>).map((loc) {
      final row = Map<String, dynamic>.from(loc as Map);
      final rentalId = row['rental_id'].toString();
      row.addAll(bikeMap[rentalId] ?? {});
      return row;
    }).toList();
  }
}

