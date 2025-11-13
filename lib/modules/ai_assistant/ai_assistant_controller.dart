import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firestore collection for storing AI assistant conversations.
const String kAiChatsCollection = 'ai_chats';

/// Temporary dev-only flag to bypass the daily quota enforcement while keeping
/// tracking active. Set back to `false` for production builds.
const bool kDevIgnoreAiAssistantQuota = true; // TODO: set to false for prod

/// Shared preferences key for persisting the preferred bot mode.
const String kAiAssistantBotModeKey = 'aiAssistant.botType';

/// Backend endpoint placeholder that proxies requests to the ChatGPT API.
///
/// Replace this URL with your deployed Firebase Function or server endpoint
/// that performs authenticated requests to OpenAI (model: `gpt-4o-mini`).
const String kAiAssistantBackendUrl =
    'https://render-deployment-placeholder.onrender.com/aiChat';

/// Allowed bot personas exposed to the user.
const Map<String, String> kBotModeLabels = {
  'general': 'عام',
  'tutor': 'تعليمي',
  'admin': 'إداري',
};

/// Additional helper descriptions for the personas.
const Map<String, String> kBotModeDescriptions = {
  'general': 'مساعد عام للاستخدام اليومي والأسئلة السريعة.',
  'tutor': 'وضع تعليمي يقدم شروحات ومراجعة للدروس.',
  'admin': 'وضع إداري للمساعدة في الإعلانات وإدارة المجتمع.',
};

/// A simple model representing a chat message.
class AiChatMessage {
  AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    required this.botType,
    this.pending = false,
  });

  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;
  final String botType;
  final bool pending;

  bool get isUser => role == 'user';

  AiChatMessage copyWith({
    bool? pending,
  }) {
    return AiChatMessage(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
      botType: botType,
      pending: pending ?? this.pending,
    );
  }
}

class _DailyLimitReached implements Exception {
  const _DailyLimitReached(this.limit);
  final int limit;

  @override
  String toString() => 'Daily message limit ($limit) reached';
}

/// Controller responsible for orchestrating AI chat interactions.
class AiAssistantController extends ChangeNotifier {
  AiAssistantController({
    cf.FirebaseFirestore? firestore,
    http.Client? httpClient,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _httpClient = httpClient ?? http.Client();

  final cf.FirebaseFirestore _firestore;
  final http.Client _httpClient;

  StreamSubscription<cf.QuerySnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _profileSubscription;
  String? _userId;
  String _plan = 'free';
  String _botMode = 'general';
  bool _initialised = false;
  bool _loading = true;
  bool _isSending = false;
  bool _limitReached = false;
  String? _errorMessage;

  List<AiChatMessage> _messages = <AiChatMessage>[];

  List<AiChatMessage> get messages => List<AiChatMessage>.unmodifiable(_messages);
  bool get loading => _loading;
  bool get isSending => _isSending;
  bool get limitReached => _limitReached;
  String? get errorMessage => _errorMessage;
  String get botMode => _botMode;
  String get plan => _plan;

  /// Initializes the controller for a user.
  Future<void> initialize({
    required String userId,
    Map<String, dynamic>? userProfile,
  }) async {
    if (_initialised && userId == _userId) {
      if (userProfile != null) {
        updateUserProfile(userProfile);
      }
      return;
    }
    _userId = userId;
    if (userProfile != null) {
      _plan = AiAssistantController.resolvePlanFromProfile(userProfile);
    } else {
      _plan = await _loadPlanFromFirestore(userId);
    }
    await _loadBotMode();
    _attachListener();
    _attachProfileListener();
    _initialised = true;
  }

  /// Updates the plan cache if the profile changes.
  void updateUserProfile(Map<String, dynamic> userProfile) {
    final String newPlan = AiAssistantController.resolvePlanFromProfile(userProfile);
    if (newPlan != _plan) {
      _plan = newPlan;
      notifyListeners();
    }
  }

  /// Forces a refresh of the selected bot mode from persistent storage.
  Future<void> refreshBotMode() async {
    await _loadBotMode();
    notifyListeners();
  }

  static String readableBotLabel(String mode) {
    return kBotModeLabels[mode] ?? 'عام';
  }

  static String readablePlanLabel(String plan) {
    if (plan.startsWith('vip_')) {
      return plan.replaceFirst('vip_', 'VIP ').toUpperCase();
    }
    switch (plan) {
      case 'gold':
        return 'Gold';
      case 'platinum':
        return 'Platinum';
      case 'silver':
        return 'Silver';
      case 'bronze':
        return 'Bronze';
      case 'plus':
        return 'Plus';
      case 'pro':
        return 'Pro';
      case 'enterprise':
        return 'Enterprise';
      default:
        return 'Free';
    }
  }

  static int dailyLimitForPlan(String plan) {
    final String lower = plan.toLowerCase();
    if (lower.contains('platinum') ||
        lower.contains('enterprise') ||
        lower.contains('ultimate') ||
        lower.contains('vip_platinum') ||
        lower.contains('vip_gold')) {
      return 20;
    }
    if (lower.contains('gold') ||
        lower.contains('plus') ||
        lower.contains('pro') ||
        lower.contains('silver') ||
        lower.contains('vip_silver') ||
        lower.contains('vip_bronze')) {
      return 10;
    }
    return 5;
  }

  Future<void> sendMessage(String rawText) async {
    final String trimmed = rawText.trim();
    if (trimmed.isEmpty || _userId == null) {
      return;
    }
    if (_isSending) {
      return;
    }

    _errorMessage = null;
    _limitReached = false;
    _isSending = true;
    notifyListeners();

    try {
      await _reserveDailySlot();
    } on _DailyLimitReached catch (err) {
      _limitReached = true;
      _errorMessage = err.toString();
      _isSending = false;
      notifyListeners();
      return;
    } on cf.FirebaseException catch (err) {
      _errorMessage = err.message ?? err.code;
      _isSending = false;
      notifyListeners();
      return;
    } catch (err) {
      _errorMessage = err.toString();
      _isSending = false;
      notifyListeners();
      return;
    }

    final cf.CollectionReference<Map<String, dynamic>> messagesRef = _firestore
        .collection(kAiChatsCollection)
        .doc(_userId)
        .collection('messages');

    final cf.DocumentReference<Map<String, dynamic>> userMessageRef =
        messagesRef.doc();
    await userMessageRef.set(<String, dynamic>{
      'role': 'user',
      'content': trimmed,
      'botType': _botMode,
      'plan': _plan,
      'createdAt': cf.FieldValue.serverTimestamp(),
      'localCreatedAt': DateTime.now().toIso8601String(),
    });

    try {
      final Map<String, dynamic> payload = <String, dynamic>{
        'userId': _userId,
        'model': 'gpt-4o-mini',
        'botType': _botMode,
        'plan': _plan,
        'messages': _buildConversationPayload(trimmed),
      };
      final http.Response response = await _httpClient.post(
        Uri.parse(kAiAssistantBackendUrl),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Backend error ${response.statusCode}: ${response.body}');
      }
      final dynamic decoded = jsonDecode(response.body);
      final String reply = _extractReply(decoded).trim();
      if (reply.isEmpty) {
        throw StateError('لم يتم استلام رد من المساعد.');
      }
      await messagesRef.add(<String, dynamic>{
        'role': 'assistant',
        'content': reply,
        'botType': _botMode,
        'plan': _plan,
        'createdAt': cf.FieldValue.serverTimestamp(),
        'localCreatedAt': DateTime.now().toIso8601String(),
      });
    } catch (err) {
      _errorMessage = err.toString();
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> _reserveDailySlot() async {
    final String? uid = _userId;
    if (uid == null) {
      throw StateError('Cannot reserve slot without userId');
    }
    final cf.DocumentReference<Map<String, dynamic>> usageRef =
        _firestore.collection(kAiChatsCollection).doc(uid);
    final String dayKey = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc());
    final int limit = dailyLimitForPlan(_plan);

    await _firestore.runTransaction((cf.Transaction tx) async {
      final cf.DocumentSnapshot<Map<String, dynamic>> snapshot =
          await tx.get(usageRef);
      int used = 0;
      String? storedDay;
      if (snapshot.exists) {
        final Map<String, dynamic>? data = snapshot.data();
        if (data != null) {
          storedDay = data['dayKey'] as String?;
          final dynamic countRaw = data['dailyCount'];
          if (storedDay == dayKey) {
            if (countRaw is int) {
              used = countRaw;
            } else if (countRaw is num) {
              used = countRaw.toInt();
            }
          } else {
            used = 0;
          }
        }
      }
      if (!kDevIgnoreAiAssistantQuota && used >= limit) {
        throw _DailyLimitReached(limit);
      }
      tx.set(
        usageRef,
        <String, dynamic>{
          'userId': uid,
          'dayKey': dayKey,
          'dailyCount': used + 1,
          'botType': _botMode,
          'plan': _plan,
          'updatedAt': cf.FieldValue.serverTimestamp(),
        },
        cf.SetOptions(merge: true),
      );
    });
  }

  List<Map<String, String>> _buildConversationPayload(String latestUserMessage) {
    final List<AiChatMessage> history = _messages.length > 10
        ? _messages.sublist(_messages.length - 10)
        : List<AiChatMessage>.from(_messages);
    final List<Map<String, String>> payload = history
        .map((AiChatMessage msg) => <String, String>{
              'role': msg.isUser ? 'user' : 'assistant',
              'content': msg.content,
            })
        .toList();
    payload.add(<String, String>{'role': 'user', 'content': latestUserMessage});
    return payload;
  }

  Future<void> _loadBotMode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _botMode = prefs.getString(kAiAssistantBotModeKey) ?? 'general';
  }

  Future<String> _loadPlanFromFirestore(String userId) async {
    try {
      final cf.DocumentSnapshot<Map<String, dynamic>> doc =
          await _firestore.collection('users').doc(userId).get();
      final Map<String, dynamic>? data = doc.data();
      if (data != null) {
        return AiAssistantController.resolvePlanFromProfile(data);
      }
    } catch (err) {
      debugPrint('AiAssistantController._loadPlanFromFirestore error: $err');
    }
    return 'free';
  }

  void _attachListener() {
    final String? uid = _userId;
    if (uid == null) {
      return;
    }
    _subscription?.cancel();
    _loading = true;
    notifyListeners();
    _subscription = _firestore
        .collection(kAiChatsCollection)
        .doc(uid)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((cf.QuerySnapshot<Map<String, dynamic>> snapshot) {
      _messages = snapshot.docs
          .map((cf.QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              _mapMessage(doc))
          .toList();
      _loading = false;
      notifyListeners();
    }, onError: (Object error) {
      _errorMessage = error.toString();
      _loading = false;
      notifyListeners();
    });
  }

  void _attachProfileListener() {
    final String? uid = _userId;
    if (uid == null) {
      return;
    }
    _profileSubscription?.cancel();
    _profileSubscription = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((cf.DocumentSnapshot<Map<String, dynamic>> snapshot) {
      final Map<String, dynamic>? data = snapshot.data();
      if (data != null) {
        updateUserProfile(data);
      }
    }, onError: (Object error) {
      debugPrint('AiAssistantController profile listener error: $error');
    });
  }

  AiChatMessage _mapMessage(cf.QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data();
    final String role = (data['role'] as String?)?.toLowerCase() == 'assistant'
        ? 'assistant'
        : 'user';
    final String content = (data['content'] as String?)?.trim() ?? '';
    final String botType = (data['botType'] as String?) ?? 'general';
    final DateTime createdAt = _parseTimestamp(data['createdAt']) ??
        _parseTimestamp(data['localCreatedAt']) ??
        DateTime.now();
    final bool pending = data['pending'] == true;
    return AiChatMessage(
      id: doc.id,
      role: role,
      content: content,
      createdAt: createdAt,
      botType: botType,
      pending: pending,
    );
  }

  DateTime? _parseTimestamp(dynamic raw) {
    if (raw is cf.Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    }
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  static String resolvePlanFromProfile(Map<String, dynamic> profile) {
    final dynamic aiPlan = profile['aiPlan'] ?? profile['plan'] ?? profile['subscription'];
    if (aiPlan is String && aiPlan.trim().isNotEmpty) {
      return aiPlan.trim().toLowerCase();
    }
    final dynamic vip = profile['vip'];
    if (vip is Map<String, dynamic>) {
      final dynamic tier = vip['tier'] ?? vip['level'];
      if (tier is String && tier.trim().isNotEmpty) {
        return 'vip_${tier.trim().toLowerCase()}';
      }
    }
    final dynamic vipTier = profile['vipTier'] ?? profile['vipLevel'];
    if (vipTier is String && vipTier.trim().isNotEmpty) {
      return 'vip_${vipTier.trim().toLowerCase()}';
    }
    return 'free';
  }

  String _extractReply(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded['reply'] is String) {
        return decoded['reply'] as String;
      }
      if (decoded['message'] is String) {
        return decoded['message'] as String;
      }
      if (decoded['data'] is Map<String, dynamic>) {
        final Map<String, dynamic> data =
            decoded['data'] as Map<String, dynamic>;
        final dynamic inner = data['reply'] ?? data['message'];
        if (inner is String) {
          return inner;
        }
      }
    }
    return decoded?.toString() ?? '';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _profileSubscription?.cancel();
    _httpClient.close();
    super.dispose();
  }
}
