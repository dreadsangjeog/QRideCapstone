import 'dart:math';

import '../models/bike.dart';
import '../models/rental.dart';
import '../models/rental_location.dart';
import '../models/rental_with_bike.dart';
import 'supabase_client.dart';

class AdminRepository {
  Future<List<Bike>> fetchBikes() async {
    final rows = await SupabaseClientProvider.client
        .from('bikes')
        .select()
        .order('code');
    return (rows as List<dynamic>)
        .map((e) => Bike.fromJson(e as Map<String, dynamic>))
        .toList();
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
        .select('*, bikes(*), profiles(username)')
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
        .select('*, bikes(*), profiles(username)');
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
        .select('*, bikes(*), profiles(username)')
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
        .select('id, bikes(code, label), profiles(username)')
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

