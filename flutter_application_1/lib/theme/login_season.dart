import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_client.dart';

enum LoginSeason { winter, summer }

const _kLoginSeason = 'qride_login_season';
const _settingKey = 'login_season';

/// Login backdrop season chosen by an admin. Website and app both follow it.
final loginSeason = ValueNotifier<LoginSeason>(LoginSeason.winter);

RealtimeChannel? _seasonChannel;

LoginSeason _parse(String? raw) =>
    raw == 'summer' ? LoginSeason.summer : LoginSeason.winter;

/// Last season this device saw. Used until the server answers.
Future<void> loadCachedLoginSeason() async {
  final prefs = await SharedPreferences.getInstance();
  loginSeason.value = _parse(prefs.getString(_kLoginSeason));
}

Future<void> _remember(LoginSeason season) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _kLoginSeason,
    season == LoginSeason.summer ? 'summer' : 'winter',
  );
}

/// Reads the admin's season and keeps listening so a switch shows up everywhere.
Future<void> syncLoginSeason() async {
  try {
    final row = await SupabaseClientProvider.client
        .from('app_settings')
        .select('value')
        .eq('key', _settingKey)
        .maybeSingle();
    final season = _parse(row?['value'] as String?);
    loginSeason.value = season;
    await _remember(season);
  } catch (e) {
    debugPrint('login season fetch failed: $e');
  }

  _seasonChannel ??= SupabaseClientProvider.client
      .channel('login-season')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'app_settings',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'key',
          value: _settingKey,
        ),
        callback: (payload) {
          final season = _parse(payload.newRecord['value'] as String?);
          loginSeason.value = season;
          _remember(season);
        },
      )
      .subscribe();
}

/// Admin only. The database rejects the change for everyone else.
Future<void> setLoginSeason(LoginSeason season) async {
  final value = season == LoginSeason.summer ? 'summer' : 'winter';
  await SupabaseClientProvider.client.from('app_settings').update({
    'value': value,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('key', _settingKey);
  loginSeason.value = season;
  await _remember(season);
}
