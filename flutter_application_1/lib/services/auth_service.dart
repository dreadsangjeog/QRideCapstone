import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Thrown when signup or resend cannot proceed because this email already has an account.
class EmailAlreadyRegisteredException implements Exception {
  const EmailAlreadyRegisteredException();

  static const userMessage =
      'This Gmail address is already in use. Sign in with your username and password, '
      'or use a different Gmail address.';

  @override
  String toString() => userMessage;
}

class AuthService {
  AuthService._();

  static Stream<AuthState> get onAuthStateChange =>
      SupabaseClientProvider.client.auth.onAuthStateChange;

  static bool get isSignedIn =>
      SupabaseClientProvider.client.auth.currentSession != null;

  static Map<String, dynamic> _functionBodyAsMap(dynamic data) {
    if (data == null) {
      throw Exception('Login service returned an empty response');
    }
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) {
        throw Exception('Login service returned an empty response');
      }
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw Exception('Login service returned an unexpected response');
  }

  /// Username + password only (Gmail is not sent from the app).
  /// Requires Edge Function `login-with-username` deployed in Supabase.
  static Future<void> signInWithUsernamePassword({
    required String username,
    required String password,
  }) async {
    try {
      final res = await SupabaseClientProvider.client.functions
          .invoke(
            'login-with-username',
            body: {
              'username': username.trim().toLowerCase(),
              'password': password,
            },
          )
          .timeout(const Duration(seconds: 15));
      final map = _functionBodyAsMap(res.data);
      final at = map['access_token'] as String?;
      final rt = map['refresh_token'] as String?;
      if (at == null || rt == null || at.isEmpty || rt.isEmpty) {
        throw Exception('Login failed');
      }
      await SupabaseClientProvider.client.auth
          .setSession(rt, accessToken: at)
          .timeout(const Duration(seconds: 15));
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String) {
        throw Exception(d['error'] as String);
      }
      throw Exception('Invalid username or password');
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception(
          'Login timed out. Check your internet and that Edge Functions are deployed.',
        );
      }
      rethrow;
    }
  }

  /// Sends a 6-digit (or project-configured) recovery code to the Gmail on file.
  /// Requires Edge Function `send-recovery-otp` deployed.
  /// Supabase must use `{{ .Token }}` in the **Reset password** email template for OTP.
  static Future<void> sendRecoveryOtpByUsername(String username) async {
    try {
      await SupabaseClientProvider.client.functions.invoke(
        'send-recovery-otp',
        body: {'username': username.trim().toLowerCase()},
      );
    } on FunctionException {
      // Always behave as success to avoid username enumeration.
    }
  }

  /// Verifies recovery OTP and sets a new password (server-side).
  /// Requires Edge Function `reset-password-with-otp` deployed.
  static Future<void> resetPasswordWithRecoveryOtp({
    required String username,
    required String token,
    required String newPassword,
  }) async {
    try {
      final res = await SupabaseClientProvider.client.functions.invoke(
        'reset-password-with-otp',
        body: {
          'username': username.trim().toLowerCase(),
          'token': token.trim(),
          'new_password': newPassword,
        },
      );
      final map = Map<String, dynamic>.from(res.data as Map);
      if (map['ok'] == true) return;
      throw Exception(map['error'] as String? ?? 'Reset failed');
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String) {
        throw Exception(d['error'] as String);
      }
      throw Exception('Invalid code or password reset failed');
    }
  }

  /// Any row in [auth.users] for this email blocks deferred signup.
  /// Requires `signup_auth_email_taken` (see supabase/migrations/024_…).
  static Future<void> _throwIfSignupAuthEmailTaken(String email) async {
    final taken = await SupabaseClientProvider.client.rpc<bool>(
      'signup_auth_email_taken',
      params: {'check_email': email.trim().toLowerCase()},
    );
    if (taken == true) {
      throw const EmailAlreadyRegisteredException();
    }
  }

  /// Sends a 6-digit code via Edge Function `request-signup-otp` (does **not** create an auth user).
  static Future<void> sendRegistrationOtp({
    required String email,
    required String password,
    required String username,
    required String firstName,
    String? middleName,
    required String lastName,
  }) async {
    final e = email.trim().toLowerCase();
    final u = username.trim().toLowerCase();
    await _throwIfSignupAuthEmailTaken(e);
    try {
      final res = await SupabaseClientProvider.client.functions
          .invoke(
            'request-signup-otp',
            body: {
              'email': e,
              'username': u,
              'password': password,
              'first_name': firstName.trim(),
              'middle_name': (middleName ?? '').trim(),
              'last_name': lastName.trim(),
            },
          )
          .timeout(const Duration(seconds: 30));
      final map = _functionBodyAsMap(res.data);
      if (map['ok'] == true) return;
      throw Exception(map['error'] as String? ?? 'Could not send verification code');
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String) {
        final msg = d['error'] as String;
        if (_isEmailTakenMessage(msg)) {
          throw const EmailAlreadyRegisteredException();
        }
        throw Exception(msg);
      }
      if (e.status == 503) {
        throw Exception(
          'Signup email is not configured on the server. '
          'Set BREVO_API_KEY or RESEND_API_KEY and SIGNUP_FROM_EMAIL on Edge Functions '
          '(see supabase/EDGE_FUNCTIONS.md).',
        );
      }
      throw Exception('Could not send verification code');
    } on TimeoutException {
      throw Exception(
        'Request timed out. Check your connection and that Edge Functions are deployed.',
      );
    }
  }

  static bool _isEmailTakenMessage(String msg) {
    final m = msg.toLowerCase();
    return m.contains('already in use') || m.contains('already registered');
  }

  /// Resend signup OTP (same body as first send; updates pending row + email).
  static Future<void> resendSignupCode({
    required String email,
    required String password,
    required String username,
    required String firstName,
    String? middleName,
    required String lastName,
  }) async {
    await sendRegistrationOtp(
      email: email,
      password: password,
      username: username,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
    );
  }

  /// Creates the confirmed auth user via Edge Function `complete-signup` (after OTP is correct).
  static Future<void> completeSignup({
    required String email,
    required String username,
    required String password,
    required String otp,
    required String firstName,
    String? middleName,
    required String lastName,
  }) async {
    final e = email.trim().toLowerCase();
    final u = username.trim().toLowerCase();
    try {
      final res = await SupabaseClientProvider.client.functions
          .invoke(
            'complete-signup',
            body: {
              'email': e,
              'username': u,
              'password': password,
              'otp': otp.trim(),
              'first_name': firstName.trim(),
              'middle_name': (middleName ?? '').trim(),
              'last_name': lastName.trim(),
            },
          )
          .timeout(const Duration(seconds: 30));
      final map = _functionBodyAsMap(res.data);
      if (map['ok'] == true) return;
      throw Exception(map['error'] as String? ?? 'Could not create account');
    } on FunctionException catch (ex) {
      final d = ex.details;
      if (d is Map && d['error'] is String) {
        throw Exception(d['error'] as String);
      }
      throw Exception('Could not create account');
    } on TimeoutException {
      throw Exception(
        'Request timed out. Check your connection and that Edge Functions are deployed.',
      );
    }
  }

  static Future<void> signOut() async {
    await SupabaseClientProvider.client.auth.signOut(
      scope: SignOutScope.global,
    );
  }

  /// Permanently deletes the signed-in rider (RPC `delete_my_account`).
  /// Fails if the user has a pending/active rental or is an admin.
  static Future<void> deleteMyAccount() async {
    try {
      await SupabaseClientProvider.client
          .rpc('delete_my_account')
          .timeout(const Duration(seconds: 20));
    } on PostgrestException catch (e) {
      throw Exception(_deleteAccountMessage(e.message, e.code));
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map && d['error'] is String
          ? d['error'] as String
          : e.toString();
      throw Exception(_deleteAccountMessage(msg, null));
    } on TimeoutException {
      throw Exception(
        'Account deletion timed out. Check your connection and try again.',
      );
    }
    try {
      await signOut();
    } catch (_) {}
  }

  static String _deleteAccountMessage(String message, String? code) {
    final m = message.toLowerCase();
    if (m.contains('open_rental')) {
      return 'Return the bike and wait until the rental has ended before deleting your account.';
    }
    if (m.contains('admin_cannot_self_delete')) {
      return 'Admin accounts cannot be deleted from the rider app.';
    }
    if (m.contains('not_signed_in')) {
      return 'Please log in again, then delete your account.';
    }
    if (m.contains('could not find the function') ||
        m.contains('does not exist') ||
        code == 'PGRST202') {
      return 'Account deletion is not enabled on the server yet. Run delete_my_account.sql in Supabase.';
    }
    return message.isEmpty ? 'Could not delete account' : message;
  }

  static Future<bool> isAdmin() async {
    final uid = SupabaseClientProvider.client.auth.currentUser?.id;
    if (uid == null) return false;
    final row = await SupabaseClientProvider.client
        .from('profiles')
        .select('role')
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return false;
    return (row['role'] as String?) == 'admin';
  }
}
