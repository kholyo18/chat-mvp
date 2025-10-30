// CODEX-BEGIN:PRIVACY_CONTROLLER
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/user_settings_service.dart';

typedef HighContrastGetter = bool Function();
typedef HighContrastSetter = void Function(bool value);

typedef ErrorHandler = void Function(Object error, StackTrace stackTrace);

class PrivacySettingsController extends ChangeNotifier {
  PrivacySettingsController(this._service);

  final UserSettingsService _service;

  PrivacySettings? _settings;
  bool _loading = true;
  String? _uid;
  StreamSubscription<PrivacySettings>? _sub;
  HighContrastGetter? _highContrastGetter;
  HighContrastSetter? _highContrastSetter;
  ErrorHandler? onError;

  PrivacySettings? get settings => _settings;
  bool get loading => _loading;

  Future<void> attach({
    required String? uid,
    HighContrastGetter? highContrastGetter,
    HighContrastSetter? highContrastSetter,
  }) async {
    _highContrastGetter = highContrastGetter;
    _highContrastSetter = highContrastSetter;
    if (_uid == uid) {
      return;
    }
    await _sub?.cancel();
    _uid = uid;
    if (uid == null) {
      _settings = null;
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      _sub = _service.watchPrivacy(uid).listen(
        (event) {
          _applySettings(event);
        },
        onError: (Object error, StackTrace stackTrace) {
          onError?.call(error, stackTrace);
        },
      );
    } catch (err, stack) {
      onError?.call(err, stack);
      _settings = PrivacySettings.defaults;
      _loading = false;
      notifyListeners();
    }
  }

  void _applySettings(PrivacySettings newSettings) {
    _settings = newSettings;
    _loading = false;
    final getter = _highContrastGetter;
    final setter = _highContrastSetter;
    if (getter != null && setter != null) {
      final current = getter();
      if (current != newSettings.highContrast) {
        setter(newSettings.highContrast);
      }
    }
    notifyListeners();
  }

  Future<void> updateCanMessage(String value) async {
    await _commit(
      patch: <String, dynamic>{'canMessage': value},
      transform: (current) => current.copyWith(canMessage: value),
    );
  }

  Future<void> updateShowOnline(bool value) async {
    await _commit(
      patch: <String, dynamic>{'showOnline': value},
      transform: (current) => current.copyWith(showOnline: value),
    );
  }

  Future<void> updateReadReceipts(bool value) async {
    await _commit(
      patch: <String, dynamic>{'readReceipts': value},
      transform: (current) => current.copyWith(readReceipts: value),
    );
  }

  Future<void> updateAllowStoriesReplies(String value) async {
    await _commit(
      patch: <String, dynamic>{'allowStoriesReplies': value},
      transform: (current) => current.copyWith(allowStoriesReplies: value),
    );
  }

  Future<void> setHighContrast(bool value, {bool applyTheme = true}) async {
    if (applyTheme) {
      final getter = _highContrastGetter;
      final setter = _highContrastSetter;
      if (getter != null && setter != null && getter() != value) {
        setter(value);
      }
    }
    await _commit(
      patch: <String, dynamic>{'highContrast': value},
      transform: (current) => current.copyWith(highContrast: value),
    );
  }

  Future<void> setHighContrastFromTheme(bool value) async {
    final current = _settings;
    if (current == null || current.highContrast == value) {
      return;
    }
    await setHighContrast(value, applyTheme: false);
  }

  Future<void> _commit({
    required Map<String, dynamic> patch,
    required PrivacySettings Function(PrivacySettings current) transform,
  }) async {
    final uid = _uid;
    final current = _settings;
    if (uid == null || current == null) {
      return;
    }
    final previous = current;
    final next = transform(current);
    _settings = next;
    notifyListeners();
    try {
      await _service.updatePrivacy(uid, patch);
    } catch (err, stack) {
      _settings = previous;
      notifyListeners();
      onError?.call(err, stack);
      rethrow;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
// CODEX-END:PRIVACY_CONTROLLER
