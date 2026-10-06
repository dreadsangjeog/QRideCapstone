import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/jwt_claims.dart';
import 'ride_foreground_task.dart';
import 'supabase_client.dart';

/// Keeps the app and the Android rental service on the same login.
///
/// Both start from one Supabase session. Supabase rotates the refresh token
/// on every renewal and revokes the whole login when a spent one is reused,
/// so after the service renews the session the app must switch to the
/// service's pair. Otherwise its next renewal signs the rider out mid-ride.
class RideSessionStorage extends LocalStorage {
  RideSessionStorage._(this._inner);

  /// Uses the same key as Supabase's default storage so riders stay signed
  /// in after updating.
  factory RideSessionStorage.forUrl(String supabaseUrl) {
    final storage = RideSessionStorage._(
      SharedPreferencesLocalStorage(
        persistSessionKey:
            'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token',
      ),
    );
    _current = storage;
    return storage;
  }

  static RideSessionStorage? _current;

  final SharedPreferencesLocalStorage _inner;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<bool> hasAccessToken() => _inner.hasAccessToken();

  /// Read on launch. If the service renewed the login while QRide was
  /// closed, starts from the service's pair instead of the spent one.
  @override
  Future<String?> accessToken() async {
    final stored = await _inner.accessToken();
    if (stored == null) return null;
    try {
      final saved = await RideForegroundTask.savedSession();
      if (saved == null) return stored;
      final session = jsonDecode(stored);
      if (session is! Map<String, dynamic>) return stored;
      final user = session['user'];
      if (user is! Map || user['id'] != saved.userId) return stored;
      final patched = _withNewerTokens(
        session,
        accessToken: saved.accessToken,
        refreshToken: saved.refreshToken,
      );
      if (patched == null) return stored;
      await _inner.persistSession(patched);
      return patched;
    } catch (_) {
      return stored;
    }
  }

  @override
  Future<void> removePersistedSession() => _inner.removePersistedSession();

  @override
  Future<void> persistSession(String persistSessionString) =>
      _inner.persistSession(persistSessionString);

  /// Switches the running app to a pair the service just renewed.
  ///
  /// No network call: the new access token is fresh, so the next request
  /// uses it and the next renewal uses the new refresh token. Supabase only
  /// saves sessions on auth events, and this change has none, so it is
  /// saved here.
  static Future<void> adoptServiceSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    final client = SupabaseClientProvider.client;
    final current = client.auth.currentSession;
    if (current == null) return;
    if (jwtClaims(accessToken)?['sub'] != current.user.id) return;
    final patched = _withNewerTokens(
      current.toJson(),
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    if (patched == null) return;
    await client.auth.recoverSession(patched);
    await _current?.persistSession(patched);
    try {
      await client.realtime.setAuth(accessToken);
    } catch (_) {}
  }

  /// Session JSON with the given pair, or null when it is the pair the
  /// session already has or is not newer than it.
  static String? _withNewerTokens(
    Map<String, dynamic> session, {
    required String accessToken,
    required String refreshToken,
  }) {
    if (accessToken.isEmpty || refreshToken.isEmpty) return null;
    if (session['refresh_token'] == refreshToken) return null;
    final nextExp = jwtExpiry(accessToken);
    if (nextExp == null) return null;
    final currentExp = jwtExpiry(session['access_token']?.toString());
    if (currentExp != null && nextExp <= currentExp) return null;
    return jsonEncode({
      ...session,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_at': nextExp,
    });
  }
}
