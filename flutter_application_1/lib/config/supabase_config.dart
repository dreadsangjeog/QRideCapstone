class SupabaseConfig {
  /// Supabase credentials (paste from Supabase dashboard).
  ///
  /// **URL:** Integrations → **Data API** → **API URL**
  /// (looks like `https://xxxxxxxx.supabase.co` — not the SQL editor, not `/rest/v1`.)
  ///
  /// **Key:** Settings → **API Keys** → **anon public**
  static const url = 'https://pvokijgypnufqpgxifjw.supabase.co';
  static const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB2b2tpamd5cG51ZnFwZ3hpZmp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1MTQ2NzUsImV4cCI6MjA5MjA5MDY3NX0.Cc0nIc-cFiH8FyMZ5_YycIuX8zcWS_-44T8FnD0iU-E';

  /// Trims accidental spaces; removes trailing slashes that can break auth calls.
  static String get effectiveUrl => url.trim().replaceAll(RegExp(r'/+$'), '');

  static String get effectiveAnonKey => anonKey.trim();

  /// Call from `main()` before [Supabase.initialize]. Throws with a clear message
  /// if values were never replaced or look wrong (common cause of startup/auth errors).
  static void assertConfigured() {
    if (url.contains('YOUR_SUPABASE') || anonKey.contains('YOUR_SUPABASE')) {
      throw StateError(
        'Set real values in lib/config/supabase_config.dart '
        '(Data API → API URL, and anon public key). Placeholder text causes auth errors.',
      );
    }
    final u = effectiveUrl;
    if (!u.startsWith('https://')) {
      throw StateError('Supabase URL must start with https://');
    }
    if (!u.contains('supabase.co')) {
      throw StateError(
        'Supabase URL should contain supabase.co (copy from Data API → API URL).',
      );
    }
    if (u.contains('/rest') || u.contains('/auth')) {
      throw StateError(
        'Use only the project base URL (e.g. https://xxxxx.supabase.co), '
        'without /rest/v1 or /auth/v1.',
      );
    }
    if (effectiveAnonKey.length < 20) {
      throw StateError(
        'Supabase anon key looks too short — paste the full anon public key.',
      );
    }
  }
}

