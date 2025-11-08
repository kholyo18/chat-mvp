import 'package:flutter/foundation.dart';

/// Centralised runtime configuration for the Agora SDK.
class AgoraConfig {
  const AgoraConfig._();

  /// TODO: replace with the real Agora App ID from console.agora.io before
  /// shipping the application.
  static const String _appId = 'e3e2e02f2a934ba68bc472b2b70d7d5c';

  /// Normalised, trimmed App ID. Throws if the App ID is missing to avoid
  /// hitting the Agora SDK with an invalid configuration.
  static String get appId {
    final value = _appId.trim();
    if (value.isEmpty || value == 'YOUR_AGORA_APP_ID') {
      throw FlutterError(
        'Missing Agora App ID. Set AgoraConfig._appId before starting calls.',
      );
    }
    return value;
  }

  /// The token to use when joining channels. Returns `null` when the project is
  /// configured to use the legacy App ID only mode.
  static String? get token => null;

  /// Convenience flag used throughout the codebase to check if a token exists.
  static bool get hasToken => false;
}
