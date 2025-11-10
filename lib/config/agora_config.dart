import 'package:flutter/foundation.dart';

/// Centralized runtime configuration for the Agora SDK.
class AgoraConfig {
  /// 🟢 ضع هنا الـ App ID الحقيقي من حسابك على Agora Console:
  /// https://console.agora.io
  static const String appId = 'e3e2e02f2a934ba68bc472b2b70d7d5c'; // ← خليه كما هو إذا هذا هو الصحيح

  /// ✅ Helper لإرجاع App ID بشكل آمن
  static String get appIdSafe {
    final value = appId.trim();
    if (value.isEmpty || value == 'YOUR_AGORA_APP_ID') {
      throw FlutterError(
        '⚠️ Missing Agora App ID.\n'
            'Set AgoraConfig.appId before starting calls.',
      );
    }
    return value;
  }

  /// Token الحالي (نستعمل null لأننا في وضع App ID only)
  static String? tokenForChannel({
    required String channelName,
    required int uid,
  }) {
    // في المستقبل نقدر نربط توليد token من السيرفر
    return null;
  }

  /// 🔤 توليد اسم قناة ثابت من الـ DM id
  static String channelNameFromDm(String dmId) {
    final sanitized = dmId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return 'dm_call_$sanitized';
  }

  /// 🔍 فحص سريع هل نستعمل token أو لا
  static bool get hasToken => false;

  /// 🔑 Token ثابت (null في وضع App ID only)
  static String? get token => null;
}
