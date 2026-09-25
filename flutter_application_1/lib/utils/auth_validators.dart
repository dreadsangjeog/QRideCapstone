/// Shared validation for auth forms.
class AuthValidators {
  AuthValidators._();

  static bool isGmailAddress(String email) {
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return false;
    final domain = e.split('@').last;
    return domain == 'gmail.com' || domain == 'googlemail.com';
  }

  static String? gmailEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Email is required';
    if (!s.contains('@')) return 'Enter a valid email';
    if (!isGmailAddress(s)) {
      return 'Use a Gmail address (@gmail.com or @googlemail.com)';
    }
    return null;
  }

  static final _personName = RegExp(r"^[A-Za-z][A-Za-z .'\-]*$");

  /// Legal name used to match the ID. Middle name may be empty.
  static String? legalName(
    String? v, {
    required String label,
    bool required = true,
  }) {
    final s = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return required ? '$label is required' : null;
    if (s.length > 40) return '$label must be at most 40 characters';
    if (!_personName.hasMatch(s)) {
      return 'Letters, spaces, hyphens, and apostrophes only';
    }
    return null;
  }

  static String? birthdate(String? v) {
    final s = (v ?? '').trim();
    final d = DateTime.tryParse(s);
    if (d == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      return 'Choose your birthdate';
    }
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    if (!d.isBefore(end)) return 'Birthdate must be in the past';
    if (d.year < 1920) return 'Enter a real birthdate';
    return null;
  }

  static String? username(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Username is required';
    if (s.length < 2) return 'Username must be at least 2 characters';
    if (s.length > 30) return 'Username must be at most 30 characters';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(s)) {
      return 'Letters, numbers, and underscore only';
    }
    return null;
  }

  static final _otp6 = RegExp(r'^\d{6}$');

  /// 6-digit Gmail / recovery OTP from Supabase.
  static String? otp6(String? v) {
    final s = (v ?? '').trim();
    if (!_otp6.hasMatch(s)) {
      return 'Enter the 6-digit code from your Gmail';
    }
    return null;
  }

  /// Registration: min 6 chars, letters + digits.
  static String? passwordRegister(String? v) {
    final s = (v ?? '');
    if (s.length < 6) return 'Use at least 6 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return 'Use letters and numbers';
    }
    return null;
  }

  /// Simple minimum length (e.g. password reset).
  static String? passwordMin6(String? v) {
    final s = (v ?? '');
    if (s.length < 6) return 'Min 6 characters';
    return null;
  }

  static String? confirmPasswordMatches(String? v, String other) {
    if ((v ?? '').isEmpty) return 'Please confirm your password';
    if (v != other) return 'Passwords do not match';
    return null;
  }
}

