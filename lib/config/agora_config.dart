import 'package:flutter/foundation.dart';

/// Centralised configuration for Agora real-time communication.
class AgoraConfig {
  const AgoraConfig._();

  /// TODO: Replace with the real Agora App ID from console.agora.io.
  static const String appId = 'b748af12acfd485997d1061d8e544783';

  /// For testing we rely on the App ID only (no token required).
  /// Keep this `null` to allow "App ID only" sessions in the Agora console.
  static const String? token = null;

  /// Returns `true` when a non-empty token is configured.
  static bool get hasToken => _normalizeToken(token) != null;

  /// Validates that the configured Agora App ID is usable and returns it.
  ///
  /// Throws a [FlutterError] when the value is empty so callers can surface a
  /// friendly message before attempting to connect to Agora.
  static String ensureValidAppId() {
    final trimmed = appId.trim();
    if (trimmed.isEmpty || trimmed == 'YOUR_AGORA_APP_ID') {
      throw FlutterError(
        'Agora App ID is missing. Update AgoraConfig.appId before trying to '
        'start an audio or video call.',
      );
    }
    return trimmed;
  }

  /// Normalises a potential token value so Agora receives `null` for
  /// "App ID only" sessions.
  static String? normalizedToken([String? candidate]) => _normalizeToken(candidate);

  static String? _normalizeToken(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
