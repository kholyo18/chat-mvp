import 'dart:async';

import 'package:flutter/foundation.dart';

/// Signature for callbacks invoked when an incoming call notification is tapped.
typedef CallNotificationTapCallback = Future<void> Function(String callId);

/// Handles display and lifecycle of DM call notifications.
///
/// The prior implementation delegated to `flutter_local_notifications` but that
/// dependency has been removed due to Android build issues.
class CallNotificationService {
  CallNotificationService._();

  /// Singleton instance for shared notification orchestration.
  static final CallNotificationService instance = CallNotificationService._();

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

    // TODO(khaled): Reintroduce local notifications for calls using a stable
    // approach if needed.
  }

  /// Cancels the notification associated with [callId], if visible.
  Future<void> cancelIncomingCallNotification(String callId) async {
    if (!_initialized) {
      return;
    }

    // TODO(khaled): Reintroduce local notifications for calls using a stable
    // approach if needed.
  }

  /// Cancels all call notifications shown by this service.
  Future<void> cancelAllCallNotifications() async {
    if (!_initialized) {
      return;
    }

    // TODO(khaled): Reintroduce local notifications for calls using a stable
    // approach if needed.
  }

  Future<void> handleNotificationTap(String callId) async {
    if (callId.isEmpty) {
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
    await callback(callId);
  }
}
