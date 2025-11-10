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

  CollectionReference<Map<String, dynamic>> _opinionsCollection(String currentUid) {
    return _firestore.collection('users').doc(currentUid).collection('opinions');
  }

  Future<UserOpinion?> getOpinion({
    required String currentUid,
    required String otherUid,
  }) async {
    try {
      final doc = await _opinionsCollection(currentUid).doc(otherUid).get();
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

  Future<void> saveOpinion({
    required String currentUid,
    required String otherUid,
    required UserOpinion opinion,
  }) async {
    try {
      final now = DateTime.now().toUtc();
      final toSave = opinion.copyWith(updatedAt: now);
      await _opinionsCollection(currentUid).doc(otherUid).set(toSave.toMap());
    } catch (err, stack) {
      debugPrint('Failed to save user opinion: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
      throw UserOpinionException('failed-to-save');
    }
  }
}
