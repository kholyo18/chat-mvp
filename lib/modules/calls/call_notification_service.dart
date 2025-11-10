import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Signature for callbacks invoked when an incoming call notification is tapped.
typedef CallNotificationTapCallback = Future<void> Function(String callId);

const String _kCallChannelId = 'dm_calls';
const String _kCallChannelName = 'DM Calls';
const String _kCallChannelDescription =
    'Incoming direct message voice and video calls';

/// Handles display and lifecycle of DM call notifications.
///
/// This service wraps [FlutterLocalNotificationsPlugin] to present heads-up
/// notifications for incoming calls. Consumers must call [init] once during
/// application startup to configure the notification channel and tap handler.
///
/// Notifications are identified by the Firestore call document ID which allows
/// the app to update or cancel a specific notification when the call state
/// changes.
class CallNotificationService {
  CallNotificationService._();

  /// Singleton instance for shared notification orchestration.
  static final CallNotificationService instance = CallNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  CallNotificationTapCallback? _onCallNotificationTap;
  bool _initialized = false;

  /// Initializes local notifications and configures the incoming call channel.
  ///
  /// The [onSelectCallNotification] callback is invoked whenever the user taps
  /// an incoming call notification while the application is running in the
  /// foreground or background.
  Future<void> init({
    required CallNotificationTapCallback onSelectCallNotification,
  }) async {
    _onCallNotificationTap = onSelectCallNotification;
    if (_initialized) {
      return;
    }

    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        unawaited(_handleNotificationResponse(response.payload));
      },
      onDidReceiveBackgroundNotificationResponse:
          callNotificationTapBackgroundHandler,
    );

    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kCallChannelId,
        _kCallChannelName,
        description: _kCallChannelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: false,
      ),
    );

    _initialized = true;
  }

  /// Presents a heads-up notification for an incoming call.
  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required bool isVideo,
    bool playSound = true,
  }) async {
    if (!_initialized) {
      if (kDebugMode) {
        debugPrint(
          '[CallNotificationService] Ignoring showIncomingCallNotification before init',
        );
      }
      return;
    }

    final notificationId = _notificationId(callId);
    final String title =
        callerName.trim().isEmpty ? 'Incoming call' : callerName.trim();
    final String body = isVideo ? 'Video call' : 'Voice call';

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _kCallChannelId,
      _kCallChannelName,
      channelDescription: _kCallChannelDescription,
      category: AndroidNotificationCategory.call,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Incoming call',
      autoCancel: false,
      ongoing: true,
      visibility: NotificationVisibility.public,
      fullScreenIntent: false,
      playSound: playSound,
    );

    final NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await _notifications.show(
      notificationId,
      title,
      body,
      details,
      payload: callId,
    );
  }

  /// Cancels the notification associated with [callId], if visible.
  Future<void> cancelIncomingCallNotification(String callId) async {
    if (!_initialized) {
      return;
    }
    await _notifications.cancel(_notificationId(callId));
  }

  /// Cancels all call notifications shown by this service.
  Future<void> cancelAllCallNotifications() async {
    if (!_initialized) {
      return;
    }
    await _notifications.cancelAll();
  }

  Future<void> _handleNotificationResponse(String? payload) async {
    if (payload == null || payload.isEmpty) {
      return;
    }
    final CallNotificationTapCallback? callback = _onCallNotificationTap;
    if (callback == null) {
      if (kDebugMode) {
        debugPrint(
          '[CallNotificationService] No callback registered for notification tap',
        );
      }
      return;
    }
    await callback(payload);
  }

  int _notificationId(String callId) => callId.hashCode & 0x7fffffff;
}

@pragma('vm:entry-point')
void callNotificationTapBackgroundHandler(NotificationResponse response) {
  final String? payload = response.payload;
  if (payload == null || payload.isEmpty) {
    return;
  }
  unawaited(CallNotificationService.instance._handleNotificationResponse(payload));
}
