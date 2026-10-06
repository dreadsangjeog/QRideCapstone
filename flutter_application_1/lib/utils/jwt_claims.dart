import 'dart:convert';

/// Payload of a JWT such as a Supabase access token. Not verified.
Map<String, dynamic>? jwtClaims(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final claims = jsonDecode(payload);
    return claims is Map<String, dynamic> ? claims : null;
  } catch (_) {
    return null;
  }
}

/// `exp` of a JWT, in seconds since the epoch.
int? jwtExpiry(String? token) {
  final exp = jwtClaims(token)?['exp'];
  return exp is num ? exp.toInt() : null;
}
