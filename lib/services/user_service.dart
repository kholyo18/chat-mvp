import 'package:cloud_firestore/cloud_firestore.dart' as cf;

import '../models/user_profile.dart';

/// Firestore backed operations for user profile data.
class UserService {
  UserService({cf.FirebaseFirestore? firestore})
      : _firestore = firestore ?? cf.FirebaseFirestore.instance;

  final cf.FirebaseFirestore _firestore;

  Future<UserProfile> getCurrentProfile(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    if (data == null) {
      return UserProfile.fromJson(const {});
    }
    return UserProfile.fromJson(data);
  }

  Future<bool> isUsernameAvailable(String username, {String? excludeUid}) async {
    final query = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(5)
        .get();
    if (query.docs.isEmpty) {
      return true;
    }
    if (excludeUid == null) {
      return false;
    }
    return query.docs.every((doc) => doc.id == excludeUid);
  }

  Future<void> saveProfile(String uid, UserProfile profile) async {
    final Map<String, dynamic> payload = profile.toJson();
    payload['updatedAt'] = cf.FieldValue.serverTimestamp();
    await _firestore
        .collection('users')
        .doc(uid)
        .set(payload, cf.SetOptions(merge: true));
  }
}
