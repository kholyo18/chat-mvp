import 'package:flutter/widgets.dart';

/// Global navigator key shared across the app to support cross-module navigation.
final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

final GlobalKey<NavigatorState> authenticatedNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'authenticatedNavigator');

NavigatorState? get rootNavigator => navigatorKey.currentState;

BuildContext? get rootNavigatorContext => navigatorKey.currentContext;

NavigatorState? get authenticatedNavigator =>
    authenticatedNavigatorKey.currentState;

BuildContext? get authenticatedNavigatorContext =>
    authenticatedNavigatorKey.currentContext;

/// Waits for the root [NavigatorState] to become available and mounted.
///
/// During app boot or immediately after authentication transitions the
/// navigator tree can briefly be rebuilt. At that point direct reads from
/// [navigatorKey.currentState] may return `null` which leads to missed
/// navigation requests (manifesting as a black screen). This helper polls the
/// key until a mounted navigator is available or throws after [timeout].
Future<NavigatorState> waitForRootNavigator({
  Duration timeout = const Duration(seconds: 5),
}) async {
  NavigatorState? navigator = navigatorKey.currentState;
  if (navigator != null && navigator.mounted) {
    return navigator;
  }

  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    navigator = navigatorKey.currentState;
    if (navigator != null && navigator.mounted) {
      return navigator;
    }
  }

  throw StateError(
    'NavigatorState was not ready within ${timeout.inMilliseconds}ms',
  );
}
