import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/user_profile.dart';
import '../../services/translate_service.dart';
import '../translator/translator_service.dart';
import 'chat_message.dart';
import 'services/chat_message_service.dart';

class ChatPresenceState {
  const ChatPresenceState({
    required this.isOnline,
    this.lastActive,
  });

  final bool isOnline;
  final DateTime? lastActive;

  String description() {
    if (isOnline) {
      return 'نشط الآن';
    }
    if (lastActive == null) {
      return 'آخر ظهور غير معروف';
    }
    final diff = DateTime.now().difference(lastActive!);
    if (diff.inMinutes < 2) {
      return 'نشط قبل لحظات';
    }
    if (diff.inMinutes < 60) {
      return 'آخر ظهور منذ ${diff.inMinutes} دقيقة';
    }
    if (diff.inHours < 24) {
      return 'آخر ظهور منذ ${diff.inHours} ساعة';
    }
    final days = diff.inDays;
    if (days == 1) {
      return 'آخر ظهور منذ يوم';
    }
    return 'آخر ظهور منذ $days أيام';
  }
}

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({
    required this.threadId,
    cf.FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    rtdb.FirebaseDatabase? realtimeDatabase,
    ImagePicker? picker,
    AudioRecorder? recorder,
    TranslatorService? translatorService,
    ChatMessageService? messageService,
  })  : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _realtimeDatabase = realtimeDatabase ?? rtdb.FirebaseDatabase.instance,
        _picker = picker ?? ImagePicker(),
        _recorder = recorder ?? AudioRecorder(),
        _translatorService = translatorService ?? TranslatorService(),
        _chatMessageService = messageService ?? ChatMessageService();

  final String threadId;
  final cf.FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final rtdb.FirebaseDatabase _realtimeDatabase;
  final ImagePicker _picker;
  final AudioRecorder _recorder;
  final TranslatorService _translatorService;
  final ChatMessageService _chatMessageService;
  final TranslateService _manualTranslator = const TranslateService();

  final Map<String, String> _inlineTranslations = <String, String>{};
  final Map<String, ChatMessage> _messageCache = <String, ChatMessage>{};
  List<String> _lastSnapshotDocIds = <String>[];

  Stream<List<ChatMessage>>? _messagesStream;

  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _threadSub;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _otherUserSub;
  StreamSubscription<rtdb.DatabaseEvent>? _presenceSub;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _typingSub;

  UserProfile? otherUserProfile;
  String? otherUid;
  ChatPresenceState presenceState = const ChatPresenceState(isOnline: false);
  bool isOtherTyping = false;
  bool isRecording = false;
  bool isUploading = false;
  bool readReceiptsEnabled = true;

  ChatMessage? replyTo;

  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;
  String? _recordedFilePath;
  Duration recordingDuration = Duration.zero;

  Timer? _typingResetTimer;
  bool _isTyping = false;
  bool _disposed = false;

  String? _currentUid;
  List<String> _members = <String>[];

  String? get currentUid => _currentUid;

  Future<void> load() async {
    _currentUid = _auth.currentUser?.uid;
    _threadSub = _firestore.collection('dm_threads').doc(threadId).snapshots().listen(
      (snapshot) {
        final data = snapshot.data();
        if (data == null) {
          return;
        }
        final members = List<String>.from((data['members'] ?? const <String>[]).cast<String>());
        if (!listEquals(members, _members)) {
          _members = members;
          final me = _currentUid;
          if (me != null) {
            final other = members.firstWhere((m) => m != me, orElse: () => me);
            if (otherUid != other) {
              otherUid = other;
              _listenToOtherUser(other);
              _listenToPresence(other);
              _listenToTyping(other);
            }
          }
        }
        notifyListeners();
      },
      onError: _reportError,
    );
  }

  void setReadReceipts(bool value) {
    if (readReceiptsEnabled == value) {
      return;
    }
    readReceiptsEnabled = value;
  }

  void _listenToOtherUser(String uid) {
    _otherUserSub?.cancel();
    _otherUserSub = _firestore.collection('users').doc(uid).snapshots().listen(
      (snapshot) {
        final data = snapshot.data();
        if (data != null) {
          otherUserProfile = UserProfile.fromJson(data);
          final rawLastSeen = data['lastSeen'];
          final lastSeen = _parseTimestamp(rawLastSeen);
          final isOnline = (data['isOnline'] as bool?) ?? false;
          presenceState = ChatPresenceState(isOnline: isOnline, lastActive: lastSeen);
        }
        notifyListeners();
      },
      onError: _reportError,
    );
  }

  void _listenToPresence(String uid) {
    _presenceSub?.cancel();
    final ref = _realtimeDatabase.ref('presence/$uid');
    _presenceSub = ref.onValue.listen(
      (event) {
        final data = event.snapshot.value;
        if (data is Map) {
          final map = Map<Object?, Object?>.from(data as Map<Object?, Object?>);
          final online = map['online'] == true;
          DateTime? lastActive;
          final rawLastActive = map['lastActive'];
          if (rawLastActive is int) {
            lastActive = DateTime.fromMillisecondsSinceEpoch(rawLastActive, isUtc: true).toLocal();
          } else if (rawLastActive is double) {
            lastActive =
                DateTime.fromMillisecondsSinceEpoch(rawLastActive.toInt(), isUtc: true).toLocal();
          }
          presenceState = ChatPresenceState(isOnline: online, lastActive: lastActive ?? presenceState.lastActive);
          notifyListeners();
        }
      },
      onError: _reportError,
    );
  }

  void _listenToTyping(String uid) {
    _typingSub?.cancel();
    _typingSub = _firestore
        .collection('dm_threads')
        .doc(threadId)
        .collection('typing')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        final data = snapshot.data();
        if (data == null) {
          isOtherTyping = false;
        } else {
          final active = data['isTyping'] == true;
          final updatedAt = _parseTimestamp(data['updatedAt']);
          if (updatedAt != null && DateTime.now().difference(updatedAt).inSeconds > 15) {
            isOtherTyping = false;
          } else {
            isOtherTyping = active;
          }
        }
        notifyListeners();
      },
      onError: _reportError,
    );
  }

  List<String> get lastSnapshotDocIds => List<String>.unmodifiable(_lastSnapshotDocIds);

  Stream<List<ChatMessage>> messagesStream() {
    return _messagesStream ??= _firestore
        .collection('dm_threads')
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limit(500)
        .snapshots()
        .map((snapshot) {
      _lastSnapshotDocIds = snapshot.docs.map((doc) => doc.id).toList(growable: false);
      final messages = snapshot.docs.map(ChatMessage.fromSnapshot).toList()
        ..sort((a, b) {
          final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final compare = ta.compareTo(tb);
          if (compare != 0) {
            return compare;
          }
          return a.id.compareTo(b.id);
        });
      _messageCache
        ..clear()
        ..addEntries(messages.map((m) => MapEntry(m.id, m)));
      return messages;
    });
  }

  ChatMessage? messageById(String? id) {
    if (id == null) {
      return null;
    }
    return _messageCache[id];
  }

  String? translatedTextFor(String messageId) => _inlineTranslations[messageId];

  Future<void> translateMessage(ChatMessage message) async {
    final text = message.text?.trim();
    if (text == null || text.isEmpty) {
      throw Exception('لا يوجد نص لترجمته');
    }
    try {
      final lang = _translatorService.targetLang;
      final translated = await _manualTranslator.translate(text, lang);
      if (translated == null || translated.trim().isEmpty) {
        throw Exception('تعذر الحصول على ترجمة');
      }
      _inlineTranslations[message.id] = translated.trim();
      notifyListeners();
    } catch (err, stack) {
      _reportError(err, stack);
      rethrow;
    }
  }

  Future<void> clearTranslation(String messageId) async {
    if (_inlineTranslations.remove(messageId) != null) {
      notifyListeners();
    }
  }

  Future<void> markMessagesAsSeen(String currentUserId) async {
    final threadRef = _firestore.collection('dm_threads').doc(threadId);
    try {
      await threadRef.set({'unread': {currentUserId: 0}}, cf.SetOptions(merge: true));
    } catch (err, stack) {
      _reportError(err, stack);
    }
    if (!readReceiptsEnabled) {
      return;
    }
    try {
      final query = await threadRef
          .collection('messages')
          .where('seenAt', isNull: true)
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      final batch = _firestore.batch();
      var hasUpdates = false;
      for (final doc in query.docs) {
        final data = doc.data();
        final senderId = (data['from'] ?? data['senderId'] ?? '') as String;
        if (senderId == currentUserId) {
          continue;
        }
        final update = <String, Object?>{
          'seenAt': cf.FieldValue.serverTimestamp(),
          'status': 'seen',
        };
        if (data['deliveredAt'] == null) {
          update['deliveredAt'] = cf.FieldValue.serverTimestamp();
        }
        hasUpdates = true;
        batch.update(doc.reference, update);
      }
      if (hasUpdates) {
        await batch.commit();
      }
    } catch (err, stack) {
      _reportError(err, stack);
    }
  }

  Future<void> markMessagesAsDelivered(Iterable<ChatMessage> messages) async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    final batch = _firestore.batch();
    var hasUpdates = false;
    for (final message in messages) {
      if (message.senderId == me) {
        continue;
      }
      final ref = message.reference;
      if (ref == null || message.deliveredAt != null) {
        continue;
      }
      final update = <String, Object?>{
        'deliveredAt': cf.FieldValue.serverTimestamp(),
      };
      if (message.seenAt == null) {
        update['status'] = 'delivered';
      }
      batch.update(ref, update);
      hasUpdates = true;
    }
    if (!hasUpdates) {
      return;
    }
    try {
      await batch.commit();
    } catch (err, stack) {
      _reportError(err, stack);
    }
  }

  Future<void> updateTyping(bool typing) async {
    if (_isTyping == typing) {
      return;
    }
    _isTyping = typing;
    _typingResetTimer?.cancel();
    final me = _currentUid;
    if (me == null) {
      return;
    }
    final doc = _firestore
        .collection('dm_threads')
        .doc(threadId)
        .collection('typing')
        .doc(me);
    try {
      await doc.set(
        {
          'isTyping': typing,
          'updatedAt': cf.FieldValue.serverTimestamp(),
        },
        cf.SetOptions(merge: true),
      );
    } catch (err, stack) {
      _reportError(err, stack);
    }
    if (typing) {
      _typingResetTimer = Timer(const Duration(seconds: 8), () => updateTyping(false));
    }
  }

  Future<void> _clearTyping() async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    try {
      await _firestore
          .collection('dm_threads')
          .doc(threadId)
          .collection('typing')
          .doc(me)
          .set(<String, Object?>{'isTyping': false, 'updatedAt': cf.FieldValue.serverTimestamp()},
              cf.SetOptions(merge: true));
    } catch (err, stack) {
      _reportError(err, stack);
    }
  }

  Future<void> setReplyTo(ChatMessage? message) async {
    if (replyTo?.id == message?.id) {
      return;
    }
    replyTo = message;
    notifyListeners();
  }

  Future<void> sendTextMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _sendMessage(
      type: ChatMessageType.text,
      payload: <String, Object?>{'text': trimmed},
      preview: trimmed,
    );
  }

  Future<void> pickFromGallery() async {
    final file = await _picker.pickMedia(requestFullMetadata: false);
    if (file == null) {
      return;
    }
    final mime = file.mimeType ?? '';
    final type = mime.startsWith('video/') ? ChatMessageType.video : ChatMessageType.image;
    await _sendMedia(file, type);
  }

  Future<void> captureFromCamera() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (file == null) {
      return;
    }
    await _sendMedia(file, ChatMessageType.image);
  }

  Future<void> _sendMedia(XFile file, ChatMessageType type) async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    isUploading = true;
    notifyListeners();
    try {
      final bytes = await file.length();
      if (bytes == 0) {
        throw Exception('الملف فارغ');
      }
      final extension = _inferExtension(file.path, file.mimeType);
      final storagePath =
          'user_uploads/$me/chats/$threadId/${DateTime.now().millisecondsSinceEpoch}$extension';
      final ref = _storage.ref(storagePath);
      final metadata = SettableMetadata(contentType: file.mimeType ?? 'application/octet-stream');
      final uploadTask = ref.putFile(File(file.path), metadata);
      final snap = await uploadTask.whenComplete(() {});
      final url = await snap.ref.getDownloadURL();
      final preview = type == ChatMessageType.image
          ? '📷 صورة'
          : type == ChatMessageType.video
              ? '🎬 فيديو'
              : 'ملف';
      await _sendMessage(
        type: type,
        payload: <String, Object?>{
          'mediaUrl': url,
          'metadata': <String, Object?>{
            'size': bytes,
            'name': file.name,
          },
        },
        preview: preview,
      );
    } catch (err, stack) {
      _reportError(err, stack);
      rethrow;
    } finally {
      isUploading = false;
      notifyListeners();
    }
  }

  Future<void> startRecording() async {
    if (isRecording) {
      return;
    }
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/chat_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _recordedFilePath = path;
    _recordingStartedAt = DateTime.now();
    recordingDuration = Duration.zero;
    isRecording = true;
    _recordingTicker?.cancel();
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_recordingStartedAt != null) {
        recordingDuration = DateTime.now().difference(_recordingStartedAt!);
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> cancelRecording() async {
    if (!isRecording) {
      return;
    }
    await _recorder.stop();
    _recordingTicker?.cancel();
    recordingDuration = Duration.zero;
    isRecording = false;
    final path = _recordedFilePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
    _recordedFilePath = null;
    notifyListeners();
  }

  Future<void> stopRecordingAndSend() async {
    if (!isRecording) {
      return;
    }
    final path = await _recorder.stop();
    _recordingTicker?.cancel();
    isRecording = false;
    notifyListeners();
    if (path == null) {
      return;
    }
    _recordedFilePath = path;
    final file = File(path);
    if (!await file.exists()) {
      return;
    }
    final duration = recordingDuration;
    recordingDuration = Duration.zero;
    await _sendAudio(file, duration);
  }

  Future<void> _sendAudio(File file, Duration duration) async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    isUploading = true;
    notifyListeners();
    try {
      final size = await file.length();
      final storagePath =
          'user_uploads/$me/chats/$threadId/${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = _storage.ref(storagePath);
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: 'audio/m4a'),
      );
      final snap = await uploadTask.whenComplete(() {});
      final url = await snap.ref.getDownloadURL();
      await _sendMessage(
        type: ChatMessageType.audio,
        payload: <String, Object?>{
          'mediaUrl': url,
          'metadata': <String, Object?>{
            'durationMs': duration.inMilliseconds,
            'size': size,
          },
        },
        preview: '🎙️ رسالة صوتية',
      );
    } catch (err, stack) {
      _reportError(err, stack);
      rethrow;
    } finally {
      isUploading = false;
      notifyListeners();
    }
  }

  Future<void> deleteForEveryone(ChatMessage message) async {
    if (message.reference == null) {
      return;
    }
    await message.reference!.update(<String, Object?>{
      'text': null,
      'mediaUrl': null,
      'mediaThumbUrl': null,
      'metadata': <String, Object?>{},
      'deletedForEveryone': true,
      'status': 'deleted',
    });
  }

  Future<void> deleteForMe(ChatMessage message) async {
    final me = _currentUid;
    if (me == null || message.reference == null) {
      return;
    }
    await message.reference!.update(<String, Object?>{
      'deletedFor': cf.FieldValue.arrayUnion(<String>[me]),
    });
  }

  /// Permanently removes a message for all participants without leaving a
  /// placeholder. This action is limited to the sender and premium users.
  Future<void> deleteMessagePermanently(ChatMessage message) async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    try {
      await _chatMessageService.deleteMessagePermanently(
        conversationId: threadId,
        messageId: message.id,
        currentUserId: me,
      );
      var shouldNotify = false;
      if (_inlineTranslations.remove(message.id) != null) {
        shouldNotify = true;
      }
      if (replyTo?.id == message.id) {
        replyTo = null;
        shouldNotify = true;
      }
      if (shouldNotify) {
        notifyListeners();
      }
    } catch (error, stack) {
      _reportError(error, stack);
      rethrow;
    }
  }

  Future<void> forwardMessage(ChatMessage message, String targetThreadId) async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    final threadRef = _firestore.collection('dm_threads').doc(targetThreadId);
    final snapshot = await threadRef.get();
    if (!snapshot.exists) {
      throw Exception('المحادثة غير موجودة');
    }
    final members = List<String>.from((snapshot.data()?['members'] ?? const <String>[]).cast<String>());
    final msgRef = threadRef.collection('messages').doc();
    final payload = <String, Object?>{
      'from': me,
      'type': message.type.value,
      'text': message.text,
      'mediaUrl': message.mediaUrl,
      'mediaThumbUrl': message.mediaThumbUrl,
      'metadata': message.metadata,
      'createdAt': cf.FieldValue.serverTimestamp(),
      'status': 'sent',
      'forwardedFromThreadId': threadId,
      'forwardedMessageId': message.id,
    };
    await msgRef.set(payload);
    await _updateThreadMetadata(
      threadRef: threadRef,
      members: members,
      preview: _previewForType(message.type, message.text),
      lastSenderId: me,
    );
  }

  Future<void> _sendMessage({
    required ChatMessageType type,
    required Map<String, Object?> payload,
    required String preview,
  }) async {
    final me = _currentUid;
    if (me == null) {
      return;
    }
    final threadRef = _firestore.collection('dm_threads').doc(threadId);
    final msgRef = threadRef.collection('messages').doc();
    final data = <String, Object?>{
      'from': me,
      'type': type.value,
      'createdAt': cf.FieldValue.serverTimestamp(),
      'sentAt': cf.FieldValue.serverTimestamp(),
      'status': 'sent',
      'replyToMessageId': replyTo?.id,
      ...payload,
    };
    await msgRef.set(data);
    final effectivePreview = preview.isNotEmpty
        ? preview
        : _previewForType(type, payload['text'] as String?);
    final members = _members.isNotEmpty
        ? _members
        : <String>[me, if (otherUid != null) otherUid!];
    await _updateThreadMetadata(
      threadRef: threadRef,
      members: members,
      preview: effectivePreview,
      lastSenderId: me,
    );
    replyTo = null;
    notifyListeners();
    unawaited(_playSendFeedback());
  }

  Future<void> _playSendFeedback() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (err) {
      if (kDebugMode) {
        debugPrint('Haptic feedback failed: $err');
      }
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (err) {
      if (kDebugMode) {
        debugPrint('System sound failed: $err');
      }
    }
  }

  Future<void> _updateThreadMetadata({
    required cf.DocumentReference<Map<String, dynamic>> threadRef,
    required List<String> members,
    required String preview,
    required String lastSenderId,
  }) async {
    final unread = <String, Object?>{};
    for (final member in members) {
      if (member == _currentUid) {
        unread[member] = 0;
      } else {
        unread[member] = cf.FieldValue.increment(1);
      }
    }
    await threadRef.set(
      <String, Object?>{
        'updatedAt': cf.FieldValue.serverTimestamp(),
        'lastMessage': preview,
        'lastSenderId': lastSenderId,
        'unread': unread,
      },
      cf.SetOptions(merge: true),
    );
  }

  String _previewForType(ChatMessageType type, String? text) {
    if (type == ChatMessageType.text) {
      return text?.trim() ?? '';
    }
    switch (type) {
      case ChatMessageType.image:
        return '📷 صورة';
      case ChatMessageType.video:
        return '🎬 فيديو';
      case ChatMessageType.audio:
        return '🎙️ رسالة صوتية';
      case ChatMessageType.file:
        return '📎 ملف';
      case ChatMessageType.system:
        return 'رسالة نظام';
      case ChatMessageType.text:
        return text?.trim() ?? '';
    }
  }

  String _inferExtension(String path, String? mimeType) {
    if (path.contains('.')) {
      return path.substring(path.lastIndexOf('.'));
    }
    if (mimeType == 'image/png') {
      return '.png';
    }
    if (mimeType == 'image/jpeg') {
      return '.jpg';
    }
    return '';
  }

  Future<void> disposeAsync() async {
    await Future.wait(<Future<void>>[
      Future.sync(() => _threadSub?.cancel()),
      Future.sync(() => _otherUserSub?.cancel()),
      Future.sync(() => _presenceSub?.cancel()),
      Future.sync(() => _typingSub?.cancel()),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    _typingResetTimer?.cancel();
    _recordingTicker?.cancel();
    unawaited(_clearTyping());
    _threadSub?.cancel();
    _otherUserSub?.cancel();
    _presenceSub?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }

  void _reportError(Object error, [StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('ChatThreadController error: $error');
    }
    if (!_disposed) {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
    }
  }

  static DateTime? _parseTimestamp(dynamic raw) {
    if (raw is cf.Timestamp) {
      return raw.toDate();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true).toLocal();
    }
    if (raw is double) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true).toLocal();
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
