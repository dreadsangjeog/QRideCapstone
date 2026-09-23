import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

const kOfflineMessage = 'It appears you are offline';

/// Short, rider-friendly copy for network / ClientException failures.
String friendlyNetworkError(Object error, {String? offlineFallback}) {
  final offline = offlineFallback ?? kOfflineMessage;
  final s = error.toString();
  final lower = s.toLowerCase();

  if (lower.contains('offline') ||
      lower.contains('clientexception') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('xmlhttprequest error') ||
      lower.contains('failed to fetch')) {
    return offline;
  }

  // Strip long "Exception: …" wrappers when we still show a custom path.
  final colon = s.indexOf(': ');
  if (colon > 0 && colon < 40 && s.length > 120) {
    return s.substring(colon + 2).trim();
  }
  if (s.length > 160) {
    return '${s.substring(0, 157)}…';
  }
  return s;
}

Future<bool> hasNetworkConnection() async {
  try {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  } catch (e) {
    debugPrint('connectivity check failed: $e');
    return true; // Don't block if the plugin fails.
  }
}
