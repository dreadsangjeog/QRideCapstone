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
        .select('*, bikes(*)')
        .eq('status', 'active')
        .order('started_at', ascending: false);
    return (rows as List<dynamic>)
        .map((e) => RentalWithBike.fromJoinedJson(e as Map<String, dynamic>))
        .toList();
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

  /// Last-known locations for active rentals, joined with bike info.
  ///
  /// This is optimized for the admin map (single round-trip for locations).
  Future<List<Map<String, dynamic>>> fetchActiveRentalLastLocationsJoined() async {
    final active = await fetchActiveRentalsWithBikes();
    final ids = active.map((e) => e.rental.id).toList();
    if (ids.isEmpty) return const [];

    final rows = await SupabaseClientProvider.client
        .from('rental_last_location')
        .select('*, rentals(*, bikes(*))')
        .inFilter('rental_id', ids);

    return (rows as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
  }
}

