import 'supabase_client.dart';

class RentalRepository {
  /// Starts a rental via RPC (updates bike status + inserts rental under RLS).
  Future<String> startRental({required String bikeId}) async {
    final user = SupabaseClientProvider.client.auth.currentUser;
    if (user == null) {
      throw StateError('User not signed in');
    }

    final result = await SupabaseClientProvider.client.rpc(
      'start_rental_for_bike',
      params: {'p_bike_id': bikeId},
    );
    if (result == null) {
      throw StateError('start_rental_for_bike returned no id');
    }
    return result.toString();
  }

  /// Ends rental via RPC (clears last location row, sets bike available).
  Future<void> endRental({required String rentalId}) async {
    await SupabaseClientProvider.client.rpc(
      'end_rental_for_user',
      params: {'p_rental_id': rentalId},
    );
  }
}
