import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../chat_message.dart';

class ChatMessageService {
  ChatMessageService({cf.FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _firestore = firestore ?? cf.FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final cf.FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Future<void> deleteMessagePermanently({
    required String conversationId,
    required String messageId,
    required String currentUserId,
  }) async {
    final threadRef = _firestore.collection('dm_threads').doc(conversationId);
    final messageRef = threadRef.collection('messages').doc(messageId);
    final snapshot = await messageRef.get();
    if (!snapshot.exists) {
      return;
    }
    final data = snapshot.data();
    if (data == null) {
      await messageRef.delete();
      await _refreshThreadMetadata(threadRef, threadData: null);
      return;
    }

    final senderId = (data['from'] ?? data['senderId'] ?? '') as String? ?? '';
    if (senderId != currentUserId) {
      // Only the author of the message is allowed to trigger a hard delete.
      return;
    }

    final threadSnapshot = await threadRef.get();
    final threadData = threadSnapshot.data();

    final storagePaths = _extractStoragePaths(data);
    try {
      await messageRef.delete();
    } on cf.FirebaseException catch (error) {
      if (error.code != 'not-found') {
        rethrow;
      }
    }

    for (final path in storagePaths) {
      try {
        await _storage.ref(path).delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          rethrow;
        }
      }
    }

    await _refreshThreadMetadata(
      threadRef,
      threadData: threadData,
    );
  }

  Set<String> _extractStoragePaths(Map<String, dynamic> data) {
    final paths = <String>{};
    void addPath(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        paths.add(value.trim());
      }
    }

    addPath(data['storagePath']);
    addPath(data['mediaStoragePath']);
    addPath(data['mediaThumbStoragePath']);

    final metadata = data['metadata'];
    if (metadata is Map) {
      addPath(metadata['storagePath']);
      addPath(metadata['thumbStoragePath']);
      final attachments = metadata['attachments'];
      if (attachments is Iterable) {
        for (final attachment in attachments) {
          if (attachment is Map) {
            addPath(attachment['storagePath']);
            addPath(attachment['thumbStoragePath']);
          } else {
            addPath(attachment);
          }
        }
      }
    }

    return paths;
  }

  Future<void> _refreshThreadMetadata(
    cf.DocumentReference<Map<String, dynamic>> threadRef, {
    required Map<String, dynamic>? threadData,
  }) async {
    final latestQuery = await threadRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latestQuery.docs.isEmpty) {
      final update = <String, Object?>{
        'lastMessage': '',
        'lastSenderId': null,
        'updatedAt': cf.FieldValue.serverTimestamp(),
      };
      if (threadData != null) {
        _clearThreadMetadataHints(update, threadData);
      }
      await threadRef.set(update, cf.SetOptions(merge: true));
      return;
    }

    final latestDoc = latestQuery.docs.first;
    final latestData = latestDoc.data();
    final message = ChatMessage.fromMap(latestData, id: latestDoc.id);
    final preview = _previewForMessage(message);
    final update = <String, Object?>{
      'lastMessage': preview,
      'lastSenderId': message.senderId,
      'updatedAt': latestData['createdAt'] ?? cf.FieldValue.serverTimestamp(),
    };

    if (threadData != null) {
      _applyThreadMetadataHints(
        update,
        threadData,
        message: message,
        preview: preview,
      );
    }

    await threadRef.set(update, cf.SetOptions(merge: true));
  }

  void _clearThreadMetadataHints(
    Map<String, Object?> update,
    Map<String, dynamic> threadData,
  ) {
    void clearIfPresent(String key) {
      if (threadData.containsKey(key)) {
        update[key] = null;
      }
    }

    clearIfPresent('lastMessageId');
    clearIfPresent('lastMessageType');
    clearIfPresent('last_message_type');
    clearIfPresent('lastType');
    clearIfPresent('last_message_kind');
    clearIfPresent('lastMessageKind');
    clearIfPresent('lastMessageMediaType');
    clearIfPresent('lastMessageCategory');
    clearIfPresent('lastMessagePayloadType');
    clearIfPresent('lastMessageContentType');

    const nestedKeys = <String>[
      'lastMessageMeta',
      'lastMessageMetadata',
      'lastMessageInfo',
      'lastMessageData',
    ];

    for (final key in nestedKeys) {
      if (threadData.containsKey(key)) {
        update[key] = null;
      }
    }
  }

  void _applyThreadMetadataHints(
    Map<String, Object?> update,
    Map<String, dynamic> threadData, {
    required ChatMessage message,
    required String preview,
  }) {
    final typeValue = message.type.value;
    final messageId = message.id;

    void writeIfPresent(String key, Object? value) {
      if (threadData.containsKey(key)) {
        update[key] = value;
      }
    }

    writeIfPresent('lastMessageId', messageId);
    writeIfPresent('lastMessageType', typeValue);
    writeIfPresent('last_message_type', typeValue);
    writeIfPresent('lastType', typeValue);
    writeIfPresent('last_message_kind', typeValue);
    writeIfPresent('lastMessageKind', typeValue);
    writeIfPresent('lastMessageMediaType', typeValue);
    writeIfPresent('lastMessageCategory', typeValue);
    writeIfPresent('lastMessagePayloadType', typeValue);
    writeIfPresent('lastMessageContentType', typeValue);

    const nestedKeys = <String>[
      'lastMessageMeta',
      'lastMessageMetadata',
      'lastMessageInfo',
      'lastMessageData',
    ];

    for (final key in nestedKeys) {
      final nested = threadData[key];
      if (nested is Map<String, dynamic>) {
        final next = Map<String, dynamic>.from(nested);
        next['type'] = typeValue;
        next['text'] = preview;
        next['senderId'] = message.senderId;
        next['messageId'] = messageId;
        update[key] = next;
      }
    }
  }

  String _previewForMessage(ChatMessage message) {
    switch (message.type) {
      case ChatMessageType.text:
        return message.text?.trim() ?? '';
      case ChatMessageType.image:
        return '📷 صورة';
      case ChatMessageType.video:
        return '🎬 فيديو';
      case ChatMessageType.audio:
        return '🎙️ رسالة صوتية';
      case ChatMessageType.file:
        return '📎 ملف';
      case ChatMessageType.system:
        return message.text?.trim() ?? '';
    }
  }
}
