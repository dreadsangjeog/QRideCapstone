/// Strips Dart's `Exception: ` prefix for user-facing text.
String stripExceptionPrefix(String raw) {
  const p = 'Exception: ';
  return raw.startsWith(p) ? raw.substring(p.length) : raw;
}
