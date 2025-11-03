import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminUserSummary {
  const AdminUserSummary({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.vipTier,
    required this.createdAt,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? email;
  final String vipTier;
  final DateTime? createdAt;
  final String? photoUrl;
}

class AdminDashboardController extends ChangeNotifier {
  AdminDashboardController({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  bool loading = false;
  String? errorMessage;
  int totalUsers = 0;
  int pendingVerifications = 0;
  int walletsWithBalance = 0;
  Map<String, int> vipCounts = <String, int>{
    'none': 0,
    'bronze': 0,
    'silver': 0,
    'gold': 0,
    'platinum': 0,
  };
  List<AdminUserSummary> recentUsers = <AdminUserSummary>[];

  static const int recentUsersLimit = 8;
  static const int walletSampleLimit = 200;

  Future<void> loadDashboard() async {
    if (loading) {
      return;
    }
    loading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final CollectionReference<Map<String, dynamic>> usersCollection =
          _firestore.collection('users');
      final CollectionReference<Map<String, dynamic>> verificationCollection =
          _firestore.collection('verification_requests');
      final CollectionReference<Map<String, dynamic>> walletCollection =
          _firestore.collection('wallet');

      totalUsers = await _countDocuments(usersCollection);

      final Map<String, int> tierCounts = await _loadVipCounts(usersCollection);
      vipCounts = tierCounts;

      pendingVerifications = await _countDocuments(
        verificationCollection.where('status', isEqualTo: 'pending'),
      );

      walletsWithBalance = await _loadWalletsWithBalance(walletCollection);

      recentUsers = await _loadRecentUsers(usersCollection);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<int> _countDocuments(Query<Map<String, dynamic>> query) async {
    final AggregateQuerySnapshot snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  Future<Map<String, int>> _loadVipCounts(
    CollectionReference<Map<String, dynamic>> usersCollection,
  ) async {
    final Map<String, int> counts = <String, int>{
      'none': 0,
      'bronze': 0,
      'silver': 0,
      'gold': 0,
      'platinum': 0,
    };

    final Map<String, List<String>> tierVariants = <String, List<String>>{
      'none': <String>['none', 'None'],
      'bronze': <String>['bronze', 'Bronze'],
      'silver': <String>['silver', 'Silver'],
      'gold': <String>['gold', 'Gold'],
      'platinum': <String>['platinum', 'Platinum', 'diamond', 'Diamond', 'titanium', 'Titanium'],
    };

    for (final MapEntry<String, List<String>> entry in tierVariants.entries) {
      final List<String> values = entry.value;
      final Query<Map<String, dynamic>> query;
      if (values.length == 1) {
        query = usersCollection.where('vipTier', isEqualTo: values.first);
      } else {
        query = usersCollection.where('vipTier', whereIn: values);
      }
      try {
        counts[entry.key] = await _countDocuments(query);
      } on FirebaseException catch (_) {
        if (values.length > 1) {
          int fallbackTotal = 0;
          for (final String value in values) {
            try {
              fallbackTotal += await _countDocuments(
                usersCollection.where('vipTier', isEqualTo: value),
              );
            } on FirebaseException catch (_) {
              // Ignore and continue aggregating known values.
            }
          }
          counts[entry.key] = fallbackTotal;
        } else {
          counts[entry.key] = 0;
        }
      }
    }

    final int knownTotal = counts.values.fold<int>(0, (int sum, int value) => sum + value);
    final int remainder = totalUsers - knownTotal;
    if (remainder > 0) {
      counts['none'] = (counts['none'] ?? 0) + remainder;
    }

    return counts;
  }

  Future<int> _loadWalletsWithBalance(
    CollectionReference<Map<String, dynamic>> walletCollection,
  ) async {
    try {
      // This intentionally limits the query to keep it lightweight. The UI
      // clarifies that the metric is approximate.
      final QuerySnapshot<Map<String, dynamic>> snapshot = await walletCollection
          .where('balance', isGreaterThan: 0)
          .limit(walletSampleLimit)
          .get();
      return snapshot.docs.length;
    } on FirebaseException catch (_) {
      return 0;
    }
  }

  Future<List<AdminUserSummary>> _loadRecentUsers(
    CollectionReference<Map<String, dynamic>> usersCollection,
  ) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await usersCollection
          .orderBy('createdAt', descending: true)
          .limit(recentUsersLimit)
          .get();
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition') {
        snapshot = await usersCollection
            .orderBy(FieldPath.documentId, descending: true)
            .limit(recentUsersLimit)
            .get();
      } else {
        rethrow;
      }
    }

    return snapshot.docs.map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final Map<String, dynamic> data = doc.data();
      final dynamic createdAtValue = data['createdAt'];
      DateTime? createdAt;
      if (createdAtValue is Timestamp) {
        createdAt = createdAtValue.toDate();
      } else if (createdAtValue is DateTime) {
        createdAt = createdAtValue;
      } else if (createdAtValue is String) {
        createdAt = DateTime.tryParse(createdAtValue);
      }

      final String vipTier = (data['vipTier'] as String?)?.toLowerCase().trim() ?? 'none';

      return AdminUserSummary(
        uid: doc.id,
        displayName: (data['displayName'] as String?)?.trim().isNotEmpty == true
            ? (data['displayName'] as String).trim()
            : 'Unknown user',
        email: (data['email'] as String?)?.trim().isNotEmpty == true
            ? (data['email'] as String).trim()
            : null,
        vipTier: vipTier.isEmpty ? 'none' : vipTier,
        createdAt: createdAt,
        photoUrl: (data['photoUrl'] as String?)?.isNotEmpty == true
            ? (data['photoUrl'] as String)
            : null,
      );
    }).toList();
  }
}
