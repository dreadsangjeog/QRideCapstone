import '../models/rental.dart';
import '../models/rental_history_row.dart';
import '../utils/rental_billing.dart';
import 'supabase_client.dart';

class RentalRepository {
  /// Fallback when the hourly fee has not been saved yet.
  static const double kRatePerHour = 50.0;

  /// Current fee for new requests. Existing rentals keep their own rate.
  Future<double> fetchHourlyRate() async {
    try {
      final row = await SupabaseClientProvider.client
          .from('rental_settings')
          .select('rate_per_hour')
          .eq('id', 1)
          .maybeSingle();
      final rate = (row?['rate_per_hour'] as num?)?.toDouble();
      if (rate != null && rate > 0) return rate;
    } catch (_) {}
    return kRatePerHour;
  }

  /// Fee changes, oldest first. Empty when the history table is not set up yet.
  Future<List<HourlyRateChange>> fetchRateHistory() async {
    try {
      final rows = await SupabaseClientProvider.client
          .from('rental_rate_history')
          .select('rate_per_hour, effective_at')
          .order('effective_at');
      final history = <HourlyRateChange>[];
      for (final row in rows as List<dynamic>) {
        if (row is! Map) continue;
        final rate = (row['rate_per_hour'] as num?)?.toDouble();
        final at = row['effective_at'];
        if (rate == null || rate <= 0 || at == null) continue;
        history.add(
          HourlyRateChange(
            ratePerHour: rate,
            effectiveAt: DateTime.parse(at.toString()),
          ),
        );
      }
      return history;
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------------

  /// Submits a rental request for [bikeId] with a chosen [plannedMinutes].
  /// The rental starts in 'pending' state until an admin approves it.
  /// Returns the new rental ID.
  Future<String> requestRental({
    required String bikeId,
    required int plannedMinutes,
  }) async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    if (user == null) throw StateError('User not signed in');

    final rate = await fetchHourlyRate();
    final result = await SupabaseClientProvider.client.rpc(
      'request_rental_for_bike',
      params: {
        'p_bike_id': bikeId,
        'p_planned_mins': plannedMinutes,
        'p_rate_per_hour': rate,
      },
    );
    if (result == null) throw StateError('request_rental_for_bike returned no id');
    return result.toString();
  }

  /// Cancels a pending rental (before admin approves).
  Future<void> cancelPendingRental({required String rentalId}) async {
    await SupabaseClientProvider.client.rpc(
      'cancel_rental_by_user',
      params: {'p_rental_id': rentalId},
    );
  }

  /// Extends an active rental by [extraMinutes] (minimum 15).
  ///
  /// Returns the saved ride. Throws if the booked time did not increase,
  /// which is what happened when the server accepted the call and wrote nothing.
  Future<Rental> extendRental({
    required String rentalId,
    required int extraMinutes,
  }) async {
    if (extraMinutes < 15) {
      throw ArgumentError.value(
        extraMinutes,
        'extraMinutes',
        'must be at least 15',
      );
    }
    final before = await fetchRentalById(rentalId);
    await SupabaseClientProvider.client.rpc(
      'extend_rental',
      params: {
        'p_rental_id': rentalId,
        'p_extra_mins': extraMinutes,
      },
    );
    final after = await fetchRentalById(rentalId);
    if (after == null || !after.isActive) {
      throw StateError('rental_not_active_or_not_owner');
    }
    final previous = before?.plannedMinutes ?? after.plannedMinutes;
    if (after.plannedMinutes < previous + extraMinutes) {
      throw StateError('extension_not_saved');
    }
    return after;
  }

  /// Fetches the current user's most recent pending or active rental.
  /// Returns null if the user has no open rental.
  Future<Rental?> fetchMyActiveRental() async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    if (user == null) return null;

    final row = await SupabaseClientProvider.client
        .from('rentals')
        .select()
        .eq('user_id', user.id)
        .inFilter('status', ['pending', 'active'])
        .order('started_at', ascending: false)
        .maybeSingle();

    if (row == null) return null;
    return Rental.fromJson(Map<String, dynamic>.from(row));
  }

  /// Fetches a specific rental by ID.
  Future<Rental?> fetchRentalById(String rentalId) async {
    final row = await SupabaseClientProvider.client
        .from('rentals')
        .select()
        .eq('id', rentalId)
        .maybeSingle();
    if (row == null) return null;
    return Rental.fromJson(Map<String, dynamic>.from(row));
  }

  /// Completed, rejected, and rider-cancelled rentals, newest first.
  Future<List<RentalHistoryRow>> fetchMyRentalHistory() async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    if (user == null) return [];

    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select('*, bikes(code, label)')
        .eq('user_id', user.id)
        .inFilter('status', ['ended', 'rejected', 'cancelled'])
        .order('started_at', ascending: false);

    return (rows as List<dynamic>).map((row) {
      final map = row as Map<String, dynamic>;
      final rental = Rental.fromJson(map);
      final bike = map['bikes'] as Map<String, dynamic>?;
      final bikeCode = bike?['code']?.toString() ?? '';
      final bikeLabel = bike?['label']?.toString().trim() ?? '';
      final displayName = bikeLabel.isNotEmpty
          ? bikeLabel
          : (bikeCode.isNotEmpty ? 'Bike $bikeCode' : 'Unknown bike');
      return RentalHistoryRow(
        rental: rental,
        bikeName: displayName,
        bikeCode: bikeCode,
      );
    }).toList();
  }
}
