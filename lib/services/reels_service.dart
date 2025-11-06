/// Service responsible for CRUD operations on Reels including upload and likes.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/reel.dart';

class ReelsService {
  ReelsService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _reelsRef =>
      _firestore.collection('reels');

  Future<Reel> uploadReel({
    required File file,
    required String caption,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('الرجاء تسجيل الدخول لنشر الريلز.');
    }

    final docRef = _reelsRef.doc();
    final storagePath = 'reels/$userId/${docRef.id}.mp4';
    final storageRef = _storage.ref(storagePath);

    final uploadTask = storageRef.putFile(
      file,
      SettableMetadata(contentType: 'video/mp4'),
    );
    await uploadTask.whenComplete(() {});

    final downloadUrl = await storageRef.getDownloadURL();

    final reel = Reel(
      id: docRef.id,
      userId: userId,
      videoUrl: downloadUrl,
      caption: caption,
      likesCount: 0,
      commentsCount: 0,
      createdAt: DateTime.now(),
      isPublic: true,
      likes: const <String>[],
    );

    await docRef.set({
      'userId': reel.userId,
      'videoUrl': reel.videoUrl,
      'caption': reel.caption,
      'likesCount': reel.likesCount,
      'commentsCount': reel.commentsCount,
      'createdAt': FieldValue.serverTimestamp(),
      'isPublic': reel.isPublic,
      'likes': <String>[],
    });

    return reel;
  }

  Stream<List<Reel>> reelsStream({int limit = 20}) {
    return _reelsRef
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Reel.fromDoc(doc))
            .where((reel) => reel.isPublic)
            .toList());
  }

  Future<void> toggleLike(String reelId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      throw Exception('الرجاء تسجيل الدخول للإعجاب بالريلز.');
    }

    final docRef = _reelsRef.doc(reelId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw Exception('الريل غير موجود.');
      }
      final data = snapshot.data() ?? <String, dynamic>{};
      final List<dynamic> likesDynamic = (data['likes'] as List<dynamic>?) ?? <dynamic>[];
      final likes = likesDynamic.whereType<String>().toSet();
      if (likes.contains(userId)) {
        likes.remove(userId);
      } else {
        likes.add(userId);
      }
      transaction.update(docRef, {
        'likes': likes.toList(),
        'likesCount': likes.length,
      });
    });
  }

  Future<bool> isLiked(String reelId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return false;
    }
    final doc = await _reelsRef.doc(reelId).get();
    if (!doc.exists) {
      return false;
    }
    final data = doc.data();
    if (data == null) {
      return false;
    }
    final List<dynamic>? likesDynamic = data['likes'] as List<dynamic>?;
    final likes = likesDynamic?.whereType<String>().toSet() ?? <String>{};
    return likes.contains(userId);
  }

  Future<void> deleteReel(String reelId) async {
    final docRef = _reelsRef.doc(reelId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      return;
    }
    final data = snapshot.data();
    if (data == null) {
      return;
    }
    final userId = data['userId'] as String?;
    final videoUrl = data['videoUrl'] as String?;
    await docRef.delete();

    if (userId != null && userId.isNotEmpty) {
      final storageRef = _storage.ref('reels/$userId/$reelId.mp4');
      try {
        await storageRef.delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') {
          rethrow;
        }
      }
    }

    if (videoUrl != null && videoUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(videoUrl).delete();
      } on FirebaseException catch (_) {
        // Ignore if already deleted or inaccessible.
      }
    }
  }
}
