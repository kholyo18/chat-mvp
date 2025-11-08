import 'package:flutter/foundation.dart';

/// Centralised runtime configuration for the Agora SDK.
class AgoraConfig {
  const AgoraConfig._();

  /// TODO: replace with the real Agora App ID from console.agora.io before
  /// shipping the application.
  static const String _appId = 'b748af12acfd485997d1061d8e544783';

  /// Optional token used when token based authentication is enabled for the
  /// Agora project. Keep this `null` while developing with an App ID only
  /// project configuration.
  static const String? _token = null;

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
  static String? get token {
    final value = _token?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// Convenience flag used throughout the codebase to check if a token exists.
  static bool get hasToken => token != null;
}
