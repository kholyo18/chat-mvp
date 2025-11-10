import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_opinion.dart';

class UserOpinionException implements Exception {
  UserOpinionException(this.message);

  final String message;

  @override
  String toString() => 'UserOpinionException: $message';
}

class UserOpinionService {
  UserOpinionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _opinionsCollection(String ownerUid) {
    return _firestore.collection('users').doc(ownerUid).collection('opinions');
  }

  Future<UserOpinion?> loadMyOpinion({
    required String currentUid,
    required String peerUid,
  }) {
    return _loadOpinion(ownerUid: currentUid, targetUid: peerUid);
  }

  Future<UserOpinion?> loadPeerOpinion({
    required String currentUid,
    required String peerUid,
  }) {
    return _loadOpinion(ownerUid: peerUid, targetUid: currentUid);
  }

  Future<UserOpinion?> getOpinion({
    required String currentUid,
    required String otherUid,
  }) {
    return loadMyOpinion(currentUid: currentUid, peerUid: otherUid);
  }

  Future<UserOpinion?> _loadOpinion({
    required String ownerUid,
    required String targetUid,
  }) async {
    try {
      final doc = await _opinionsCollection(ownerUid).doc(targetUid).get();
      final data = doc.data();
      if (data == null) {
        return null;
      }
      return UserOpinion.fromMap(data);
    } catch (err, stack) {
      debugPrint('Failed to load user opinion: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      throw UserOpinionException('failed-to-load');
    }
  }

  Future<void> saveMyOpinion({
    required String currentUid,
    required String peerUid,
    required UserOpinion opinion,
  }) {
    return _saveOpinion(ownerUid: currentUid, targetUid: peerUid, opinion: opinion);
  }

  Future<void> saveOpinion({
    required String currentUid,
    required String otherUid,
    required UserOpinion opinion,
  }) {
    return saveMyOpinion(currentUid: currentUid, peerUid: otherUid, opinion: opinion);
  }

  Future<void> _saveOpinion({
    required String ownerUid,
    required String targetUid,
    required UserOpinion opinion,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final toSave = opinion.copyWith(updatedAt: now);
      await _opinionsCollection(ownerUid).doc(targetUid).set(toSave.toMap());
    } catch (err, stack) {
      debugPrint('Failed to save user opinion: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      throw UserOpinionException('failed-to-save');
    }
  }
}
