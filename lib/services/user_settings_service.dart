// CODEX-BEGIN:USER_SETTINGS_SERVICE
import 'package:cloud_firestore/cloud_firestore.dart' as cf;

class PrivacySettings {
  const PrivacySettings({
    required this.canMessage,
    required this.showOnline,
    required this.readReceipts,
    required this.allowStoriesReplies,
    required this.highContrast,
    required this.shareTypingPreview,
  });

  final String canMessage;
  final bool showOnline;
  final bool readReceipts;
  final String allowStoriesReplies;
  final bool highContrast;
  final bool shareTypingPreview;

  static const PrivacySettings defaults = PrivacySettings(
    canMessage: 'everyone',
    showOnline: true,
    readReceipts: true,
    allowStoriesReplies: 'everyone',
    highContrast: false,
    shareTypingPreview: false,
  );

  PrivacySettings copyWith({
    String? canMessage,
    bool? showOnline,
    bool? readReceipts,
    String? allowStoriesReplies,
    bool? highContrast,
    bool? shareTypingPreview,
  }) {
    return PrivacySettings(
      canMessage: canMessage ?? this.canMessage,
      showOnline: showOnline ?? this.showOnline,
      readReceipts: readReceipts ?? this.readReceipts,
      allowStoriesReplies: allowStoriesReplies ?? this.allowStoriesReplies,
      highContrast: highContrast ?? this.highContrast,
      shareTypingPreview: shareTypingPreview ?? this.shareTypingPreview,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'canMessage': canMessage,
      'showOnline': showOnline,
      'readReceipts': readReceipts,
      'allowStoriesReplies': allowStoriesReplies,
      'highContrast': highContrast,
      'shareTypingPreview': shareTypingPreview,
    };
  }

  static PrivacySettings fromMap(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return defaults;
    }
    return PrivacySettings(
      canMessage: (data['canMessage'] as String?)?.trim().toLowerCase() ?? defaults.canMessage,
      showOnline: (data['showOnline'] as bool?) ?? defaults.showOnline,
      readReceipts: (data['readReceipts'] as bool?) ?? defaults.readReceipts,
      allowStoriesReplies:
          (data['allowStoriesReplies'] as String?)?.trim().toLowerCase() ?? defaults.allowStoriesReplies,
      highContrast: (data['highContrast'] as bool?) ?? defaults.highContrast,
      shareTypingPreview: (data['shareTypingPreview'] as bool?) ?? defaults.shareTypingPreview,
    );
  }
}

class UserSettingsService {
  UserSettingsService({cf.FirebaseFirestore? firestore}) : _firestore = firestore ?? cf.FirebaseFirestore.instance;

  final cf.FirebaseFirestore _firestore;

  cf.DocumentReference<Map<String, dynamic>> _privacyDoc(String uid) {
    return _firestore.collection('users').doc(uid).collection('settings').doc('privacy');
  }

  Future<void> ensureDefaults(String uid) async {
    final docRef = _privacyDoc(uid);
    await docRef.set(PrivacySettings.defaults.toMap(), cf.SetOptions(merge: true));
  }

  Stream<PrivacySettings> watchPrivacy(String uid) async* {
    final docRef = _privacyDoc(uid);
    await ensureDefaults(uid);
    yield* docRef.snapshots().map((snapshot) => PrivacySettings.fromMap(snapshot.data()));
  }

  Future<PrivacySettings> fetchPrivacy(String uid) async {
    final docRef = _privacyDoc(uid);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      await ensureDefaults(uid);
      return PrivacySettings.defaults;
    }
    return PrivacySettings.fromMap(snapshot.data());
  }

  Future<void> updatePrivacy(String uid, Map<String, dynamic> patch) async {
    final docRef = _privacyDoc(uid);
    await docRef.set(patch, cf.SetOptions(merge: true));
  }
}
// CODEX-END:USER_SETTINGS_SERVICE
