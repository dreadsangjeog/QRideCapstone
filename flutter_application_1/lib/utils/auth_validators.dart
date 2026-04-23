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

}
