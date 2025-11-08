class AgoraConfig {
  const AgoraConfig._();

  /// TODO: replace with the real Agora App ID from console.agora.io.
  static const String appId = 'b748af12acfd485997d1061d8e544783';

  /// For testing we rely on the App ID only (no token required).
  /// Keep this `null` to allow "App ID only" sessions in the Agora console.
  static const String? token = null;
}
