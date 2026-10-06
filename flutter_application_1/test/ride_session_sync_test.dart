import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/services/ride_session_sync.dart';
import 'package:flutter_application_1/services/ride_timer_alerts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sessionKey = 'sb-demo-auth-token';
const _taskPrefix = 'com.pravera.flutter_foreground_task.prefs.';

String _jwt({required String sub, required int exp}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'sub': sub, 'exp': exp})}.sig';
}

String _session({required String access, required String refresh}) {
  return jsonEncode({
    'access_token': access,
    'refresh_token': refresh,
    'token_type': 'bearer',
    'user': {'id': 'rider-1'},
  });
}

Future<Map<String, dynamic>> _launchSession(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = RideSessionStorage.forUrl('https://demo.supabase.co');
  await storage.initialize();
  final json = await storage.accessToken();
  return jsonDecode(json!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  final appAccess = _jwt(sub: 'rider-1', exp: 1000);
  final serviceAccess = _jwt(sub: 'rider-1', exp: 4600);

  test('launch picks up the pair the ride service renewed', () async {
    final session = await _launchSession({
      _sessionKey: _session(access: appAccess, refresh: 'spent'),
      '${_taskPrefix}qride_user_id': 'rider-1',
      '${_taskPrefix}qride_access_token': serviceAccess,
      '${_taskPrefix}qride_refresh_token': 'fresh',
    });

    expect(session['refresh_token'], 'fresh');
    expect(session['access_token'], serviceAccess);
    expect(session['expires_at'], 4600);

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString(_sessionKey)!);
    expect(saved['refresh_token'], 'fresh');
  });

  test('launch keeps the app pair when it is the newer one', () async {
    final session = await _launchSession({
      _sessionKey: _session(access: serviceAccess, refresh: 'newest'),
      '${_taskPrefix}qride_user_id': 'rider-1',
      '${_taskPrefix}qride_access_token': appAccess,
      '${_taskPrefix}qride_refresh_token': 'older',
    });

    expect(session['refresh_token'], 'newest');
  });

  test('launch ignores a service login for another rider', () async {
    final session = await _launchSession({
      _sessionKey: _session(access: appAccess, refresh: 'mine'),
      '${_taskPrefix}qride_user_id': 'rider-2',
      '${_taskPrefix}qride_access_token': _jwt(sub: 'rider-2', exp: 4600),
      '${_taskPrefix}qride_refresh_token': 'theirs',
    });

    expect(session['refresh_token'], 'mine');
  });

  test('timer alert goes out once per end time', () async {
    SharedPreferences.setMockInitialValues({});
    final end = DateTime.utc(2026, 10, 5, 13);

    final first = await RideTimerAlert.fiveMinutes.claim(
      rentalId: 'r1',
      scheduledEnd: end,
    );
    final repeat = await RideTimerAlert.fiveMinutes.claim(
      rentalId: 'r1',
      scheduledEnd: end,
    );
    final otherAlert = await RideTimerAlert.overtime.claim(
      rentalId: 'r1',
      scheduledEnd: end,
    );
    final afterExtension = await RideTimerAlert.fiveMinutes.claim(
      rentalId: 'r1',
      scheduledEnd: end.add(const Duration(minutes: 30)),
    );

    expect(first, isTrue);
    expect(repeat, isFalse);
    expect(otherAlert, isTrue);
    expect(afterExtension, isTrue);
  });
}
