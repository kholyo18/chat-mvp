import 'package:flutter/widgets.dart';

/// Global navigator key shared across the app to support cross-module navigation.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

NavigatorState? get rootNavigator => navigatorKey.currentState;

BuildContext? get rootNavigatorContext => navigatorKey.currentContext;
