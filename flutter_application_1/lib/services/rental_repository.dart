import '../models/rental.dart';
import '../models/rental_history_row.dart';
import 'supabase_client.dart';

class RentalRepository {
  /// Fixed rate per hour in Philippine Peso.
  static const double kRatePerHour = 50.0;

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

    final result = await SupabaseClientProvider.client.rpc(
      'request_rental_for_bike',
      params: {
        'p_bike_id': bikeId,
        'p_planned_mins': plannedMinutes,
        'p_rate_per_hour': kRatePerHour,
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

  /// Completed and rejected rentals for the signed-in user, newest first.
  Future<List<RentalHistoryRow>> fetchMyRentalHistory() async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    if (user == null) return [];

    final rows = await SupabaseClientProvider.client
        .from('rentals')
        .select('*, bikes(code, label)')
        .eq('user_id', user.id)
        .inFilter('status', ['ended', 'rejected'])
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
