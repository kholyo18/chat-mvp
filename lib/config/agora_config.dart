class AgoraConfig {
  const AgoraConfig._();

  /// TODO: replace with the real Agora App ID from console.agora.io.
  static const String appId = 'YOUR_AGORA_APP_ID';

  /// For testing we rely on the App ID only (no token required).
  static const String? token = null;
}
