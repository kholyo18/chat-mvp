// CODEX-BEGIN:STORE_FIRESTORE_SERVICE
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

sealed class SafeResult<T> {
  const SafeResult();
}

class SafeSuccess<T> extends SafeResult<T> {
  const SafeSuccess(this.value);

  final T value;
}

class SafeFailure<T> extends SafeResult<T> {
  const SafeFailure({
    required this.error,
    required this.stackTrace,
    required this.message,
  });

  final Object error;
  final StackTrace stackTrace;
  final String message;
}

Future<SafeResult<T>> safeRequest<T>(
  Future<T> Function() request, {
  String? debugLabel,
}) async {
  try {
    final value = await request();
    return SafeSuccess<T>(value);
  } catch (err, stack) {
    final label = debugLabel ?? T.toString();
    debugPrint('safeRequest($label) failed: $err');
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: err,
        stack: stack,
        informationCollector: () => [
          if (debugLabel != null)
            DiagnosticsProperty<String>('safeRequest.label', debugLabel),
        ],
      ),
    );
    return SafeFailure<T>(
      error: err,
      stackTrace: stack,
      message: err is Exception ? err.toString() : '$err',
    );
  }
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

double? _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

DateTime? _parseDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is DateTime) {
    return value;
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

Map<String, dynamic> _cloneMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.from(source);
}

class StoreItem {
  const StoreItem({
    required this.id,
    required this.coins,
    this.label,
    this.price,
    this.sku,
    this.createdAt,
    required this.raw,
  });

  final String id;
  final int coins;
  final String? label;
  final double? price;
  final String? sku;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory StoreItem.fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = _cloneMap(doc.data());
    final dynamic coinsRaw = data['coins'] ?? data['amount'] ?? data['quantity'];
    final dynamic priceRaw = data['price'] ?? data['fiatPrice'] ?? data['amountFiat'];
    final dynamic skuRaw = data['sku'] ?? data['productId'] ?? data['skuId'];
    final dynamic labelRaw = data['label'] ?? data['title'] ?? data['name'];
    final createdAt = _parseDateTime(data['createdAt']);

    return StoreItem(
      id: doc.id,
      coins: _parseInt(coinsRaw),
      label: labelRaw is String ? labelRaw : null,
      price: _parseDouble(priceRaw),
      sku: skuRaw is String ? skuRaw : skuRaw?.toString(),
      createdAt: createdAt,
      raw: Map<String, dynamic>.unmodifiable(data),
    );
  }

  factory StoreItem.fromJson(Map<String, dynamic> json) {
    final rawData = json['raw'];
    Map<String, dynamic> raw = const {};
    if (rawData is Map<String, dynamic>) {
      raw = Map<String, dynamic>.from(rawData);
    } else if (rawData is Map) {
      raw =
          Map<String, dynamic>.from(rawData as Map<dynamic, dynamic>);
    }
    return StoreItem(
      id: (json['id'] as String?) ?? '',
      coins: _parseInt(json['coins']),
      label: json['label'] as String?,
      price: _parseDouble(json['price']),
      sku: (json['sku'] as String?) ?? raw['sku']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['createdAt'] as num).toInt())
          : _parseDateTime(raw['createdAt']),
      raw: Map<String, dynamic>.unmodifiable(raw),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'coins': coins,
      if (label != null) 'label': label,
      if (price != null) 'price': price,
      if (sku != null) 'sku': sku,
      if (createdAt != null) 'createdAt': createdAt!.millisecondsSinceEpoch,
      'raw': raw,
    };
  }
}

class StorePagePayload {
  const StorePagePayload({
    required this.items,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<StoreItem> items;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

// CODEX-BEGIN:WALLET_FIRESTORE_MODELS
class WalletSummary {
  const WalletSummary({
    required this.balance,
    required this.vipTier,
    required this.raw,
  });

  final int balance;
  final String vipTier;
  final Map<String, dynamic> raw;

  factory WalletSummary.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? <String, dynamic>{};
    final map = _cloneMap(Map<String, dynamic>.from(data));
    return WalletSummary(
      balance: _parseInt(map['balance']),
      vipTier: (map['vipTier'] as String?) ?? 'Bronze',
      raw: Map<String, dynamic>.unmodifiable(map),
    );
  }

  factory WalletSummary.fromJson(Map<String, dynamic> json) {
    return WalletSummary(
      balance: _parseInt(json['balance']),
      vipTier: (json['vipTier'] as String?) ?? 'Bronze',
      raw: Map<String, dynamic>.unmodifiable(Map<String, dynamic>.from(json)),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'balance': balance,
      'vipTier': vipTier,
    };
  }
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.createdAt,
    required this.raw,
  });

  final String id;
  final int amount;
  final String type;
  final DateTime createdAt;
  final Map<String, dynamic> raw;

  factory WalletTransaction.fromQueryDocument(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = _cloneMap(doc.data());
    return WalletTransaction(
      id: (data['id'] as String?) ?? doc.id,
      amount: _parseInt(data['amount']),
      type: (data['type'] as String?) ?? '',
      createdAt:
          _parseDateTime(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      raw: Map<String, dynamic>.unmodifiable(data),
    );
  }

  factory WalletTransaction.fromMap(Map<String, dynamic> data) {
    final cloned = _cloneMap(Map<String, dynamic>.from(data));
    return WalletTransaction(
      id: (cloned['id'] as String?) ?? '',
      amount: _parseInt(cloned['amount']),
      type: (cloned['type'] as String?) ?? '',
      createdAt:
          _parseDateTime(cloned['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      raw: Map<String, dynamic>.unmodifiable(cloned),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'amount': amount,
      'type': type,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }
}

class WalletTransactionsPage {
  const WalletTransactionsPage({
    required this.transactions,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<WalletTransaction> transactions;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}
// CODEX-END:WALLET_FIRESTORE_MODELS

// CODEX-BEGIN:CHAT_FIRESTORE_MODELS
class DiscoverUser {
  const DiscoverUser({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.vipTier,
    required this.followers,
    required this.following,
    required this.raw,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;
  final String vipTier;
  final int followers;
  final int following;
  final Map<String, dynamic> raw;

  factory DiscoverUser.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = _cloneMap(doc.data());
    return DiscoverUser(
      uid: doc.id,
      displayName: (data['displayName'] as String?) ?? 'User',
      photoUrl: data['photoUrl'] as String?,
      vipTier: (data['vipTier'] as String?) ?? (data['vipLevel'] as String?) ?? 'Bronze',
      followers: _parseInt(data['followers']),
      following: _parseInt(data['following']),
      raw: Map<String, dynamic>.unmodifiable(data),
    );
  }
}

class DiscoverUsersPage {
  const DiscoverUsersPage({
    required this.users,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<DiscoverUser> users;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

class InboxThreadItem {
  const InboxThreadItem({
    required this.id,
    required this.members,
    required this.lastMessage,
    required this.updatedAt,
    required this.unread,
    required this.raw,
  });

  final String id;
  final List<String> members;
  final String? lastMessage;
  final Timestamp? updatedAt;
  final Map<String, int> unread;
  final Map<String, dynamic> raw;

  factory InboxThreadItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = _cloneMap(doc.data());
    final members = List<String>.from((data['members'] ?? const <String>[]).cast<String>());
    final rawUnread = (data['unread'] as Map?) ?? const <String, dynamic>{};
    final normalizedUnread = <String, int>{};
    for (final entry in rawUnread.entries) {
      final key = entry.key.toString();
      normalizedUnread[key] = _parseInt(entry.value);
    }
    return InboxThreadItem(
      id: doc.id,
      members: List<String>.unmodifiable(members),
      lastMessage: data['lastMessage'] as String?,
      updatedAt: data['updatedAt'] as Timestamp?,
      unread: Map<String, int>.unmodifiable(normalizedUnread),
      raw: Map<String, dynamic>.unmodifiable(data),
    );
  }
}

class InboxThreadsPage {
  const InboxThreadsPage({
    required this.threads,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<InboxThreadItem> threads;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}
// CODEX-END:CHAT_FIRESTORE_MODELS

// CODEX-BEGIN:STORY_FIRESTORE_MODELS
enum StoryType {
  text,
  image,
  video,
}

extension StoryTypeParser on StoryType {
  String get value {
    switch (this) {
      case StoryType.text:
        return 'text';
      case StoryType.image:
        return 'image';
      case StoryType.video:
        return 'video';
    }
  }

  static StoryType fromValue(String raw) {
    switch (raw) {
      case 'image':
        return StoryType.image;
      case 'video':
        return StoryType.video;
      case 'text':
      default:
        return StoryType.text;
    }
  }
}

enum StoryPrivacy {
  public,
  contacts,
  custom,
}

extension StoryPrivacyParser on StoryPrivacy {
  String get value {
    switch (this) {
      case StoryPrivacy.public:
        return 'public';
      case StoryPrivacy.contacts:
        return 'contacts';
      case StoryPrivacy.custom:
        return 'custom';
    }
  }

  static StoryPrivacy fromValue(String raw) {
    switch (raw) {
      case 'contacts':
        return StoryPrivacy.contacts;
      case 'custom':
        return StoryPrivacy.custom;
      case 'public':
      default:
        return StoryPrivacy.public;
    }
  }
}

class Story {
  const Story({
    required this.id,
    required this.uid,
    required this.type,
    required this.privacy,
    required this.viewers,
    required this.createdAt,
    this.text,
    this.mediaUrl,
    this.bgColor,
    this.allowedUids = const <String>[],
    this.isPending = false,
  });

  final String id;
  final String uid;
  final StoryType type;
  final StoryPrivacy privacy;
  final int viewers;
  final DateTime createdAt;
  final String? text;
  final String? mediaUrl;
  final String? bgColor;
  final List<String> allowedUids;
  final bool isPending;

  bool isActive(DateTime now) {
    return createdAt.isAfter(now.subtract(const Duration(hours: 24)));
  }

  bool canBeViewedBy(
    String viewerUid, {
    Set<String> contactUids = const <String>{},
  }) {
    if (viewerUid == uid) {
      return true;
    }
    switch (privacy) {
      case StoryPrivacy.public:
        return true;
      case StoryPrivacy.contacts:
        return contactUids.contains(uid);
      case StoryPrivacy.custom:
        return allowedUids.contains(viewerUid);
    }
  }

  Story copyWith({
    String? id,
    String? uid,
    StoryType? type,
    StoryPrivacy? privacy,
    int? viewers,
    DateTime? createdAt,
    String? text,
    String? mediaUrl,
    String? bgColor,
    List<String>? allowedUids,
    bool? isPending,
  }) {
    return Story(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      type: type ?? this.type,
      privacy: privacy ?? this.privacy,
      viewers: viewers ?? this.viewers,
      createdAt: createdAt ?? this.createdAt,
      text: text ?? this.text,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      bgColor: bgColor ?? this.bgColor,
      allowedUids: allowedUids ?? this.allowedUids,
      isPending: isPending ?? this.isPending,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'uid': uid,
      'type': type.value,
      'privacy': privacy.value,
      'viewers': viewers,
      'createdAt': Timestamp.fromDate(createdAt),
      if (text != null) 'text': text,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (bgColor != null) 'bgColor': bgColor,
      if (allowedUids.isNotEmpty) 'allowedUids': allowedUids,
    };
  }

  factory Story.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return Story.fromMap(doc.id, doc.data());
  }

  factory Story.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return Story.fromMap(snapshot.id, snapshot.data() ?? <String, dynamic>{});
  }

  factory Story.fromMap(String id, Map<String, dynamic> data) {
    final createdAt = _parseDateTime(data['createdAt']) ?? DateTime.now();
    final allowed = data['allowedUids'];
    return Story(
      id: data['id'] is String && (data['id'] as String).isNotEmpty
          ? data['id'] as String
          : id,
      uid: (data['uid'] as String?) ?? '',
      type: StoryTypeParser.fromValue((data['type'] as String?) ?? 'text'),
      privacy:
          StoryPrivacyParser.fromValue((data['privacy'] as String?) ?? 'public'),
      viewers: _parseInt(data['viewers']),
      createdAt: createdAt,
      text: data['text'] as String?,
      mediaUrl: data['mediaUrl'] as String?,
      bgColor: data['bgColor'] as String?,
      allowedUids: allowed is Iterable
          ? List<String>.unmodifiable(
              allowed.map((dynamic item) => item.toString()),
            )
          : const <String>[],
      isPending: false,
    );
  }
}
// CODEX-END:STORY_FIRESTORE_MODELS

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<StorePagePayload> fetchStorePage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('store')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final docs = snapshot.docs;
    final items = docs.map(StoreItem.fromDocument).toList();
    final last = docs.isNotEmpty ? docs.last : startAfter;
    final hasMore = docs.length == limit;
    return StorePagePayload(items: items, lastDocument: last, hasMore: hasMore);
  }

  // CODEX-BEGIN:WALLET_FIRESTORE_METHODS
  Stream<WalletSummary?> walletStream(String uid) {
    return _firestore.collection('wallet').doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      return WalletSummary.fromSnapshot(doc);
    });
  }

  Future<SafeResult<WalletTransactionsPage>> fetchWalletTransactions({
    required String uid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    return safeRequest<WalletTransactionsPage>(() async {
      Query<Map<String, dynamic>> query = _firestore
          .collection('wallet')
          .doc(uid)
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final docs = snapshot.docs;
      final items = docs.map(WalletTransaction.fromQueryDocument).toList();
      final lastDoc = docs.isNotEmpty ? docs.last : startAfter;
      final hasMore = docs.length == limit;
      return WalletTransactionsPage(
        transactions: items,
        lastDocument: lastDoc,
        hasMore: hasMore,
      );
    }, debugLabel: 'fetchWalletTransactions');
  }

  Future<SafeResult<WalletTransaction>> simulateWalletTopUp({
    required String uid,
    required int amount,
    required String packId,
  }) {
    return safeRequest<WalletTransaction>(() async {
      final walletRef = _firestore.collection('wallet').doc(uid);
      final txRef = walletRef.collection('transactions').doc();
      final Timestamp createdAt = Timestamp.now();

      final WalletTransaction transactionResult = await _firestore
          .runTransaction<WalletTransaction>((transaction) async {
        final walletSnapshot = await transaction.get(walletRef);
        final data = walletSnapshot.data() ?? <String, dynamic>{};
        final currentBalance = _parseInt(data['balance']);
        final vipTier = (data['vipTier'] as String?) ?? 'Bronze';
        final newBalance = currentBalance + amount;

        transaction.set(
          walletRef,
          <String, dynamic>{
            'balance': newBalance,
            'vipTier': vipTier,
          },
          SetOptions(merge: true),
        );

        final payload = <String, dynamic>{
          'id': txRef.id,
          'amount': amount,
          'type': 'purchase',
          'createdAt': createdAt,
          'packId': packId,
        };

        transaction.set(txRef, payload);
        return WalletTransaction.fromMap(payload);
      });

      return transactionResult;
    }, debugLabel: 'simulateWalletTopUp');
  }
  // CODEX-END:WALLET_FIRESTORE_METHODS

  // CODEX-BEGIN:STORY_FIRESTORE_METHODS
  CollectionReference<Map<String, dynamic>> get _storiesCollection {
    return _firestore.collection('stories');
  }

  Future<SafeResult<Story>> createStory({
    required String uid,
    required StoryType type,
    required StoryPrivacy privacy,
    required DateTime createdAt,
    String? text,
    String? mediaUrl,
    String? bgColor,
    List<String>? allowedUids,
  }) {
    return safeRequest<Story>(() async {
      final docRef = _storiesCollection.doc();
      final Map<String, dynamic> payload = <String, dynamic>{
        'id': docRef.id,
        'uid': uid,
        'type': type.value,
        'privacy': privacy.value,
        'viewers': 0,
        'createdAt': Timestamp.fromDate(createdAt),
        if (text != null) 'text': text,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (bgColor != null) 'bgColor': bgColor,
      };
      if (privacy == StoryPrivacy.custom && allowedUids != null) {
        payload['allowedUids'] = allowedUids;
      }
      await docRef.set(payload);
      return Story.fromMap(docRef.id, payload);
    }, debugLabel: 'createStory');
  }

  Stream<List<Story>> latestPublicStories({int limit = 50}) {
    final Timestamp cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    return _storiesCollection
        .where('privacy', isEqualTo: StoryPrivacy.public.value)
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Story.fromDocument).toList());
  }

  Stream<List<Story>> storiesForViewer({
    required String viewerUid,
    Set<String> contactUids = const <String>{},
    int limit = 100,
  }) {
    final Timestamp cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    final Set<String> normalizedContacts = Set<String>.from(contactUids);
    normalizedContacts.add(viewerUid);
    return _storiesCollection
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final stories = snapshot.docs.map(Story.fromDocument).toList();
      return stories
          .where(
            (story) => story.canBeViewedBy(
              viewerUid,
              contactUids: normalizedContacts,
            ),
          )
          .toList();
    });
  }

  Stream<List<Story>> storiesForUser(String uid) {
    final Timestamp cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 24)),
    );
    return _storiesCollection
        .where('uid', isEqualTo: uid)
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Story.fromDocument).toList());
  }

  Stream<bool> hasActiveStory(String uid) {
    return storiesForUser(uid).map((stories) {
      final DateTime now = DateTime.now();
      return stories.any((story) => story.isActive(now));
    });
  }

  Future<SafeResult<void>> incrementStoryViewers(String storyId) {
    return safeRequest<void>(() async {
      final DocumentReference<Map<String, dynamic>> doc =
          _storiesCollection.doc(storyId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(doc);
        final current = _parseInt(snapshot.data()?['viewers']);
        transaction.set(
          doc,
          <String, dynamic>{'viewers': current + 1},
          SetOptions(merge: true),
        );
      });
    }, debugLabel: 'incrementStoryViewers');
  }
  // CODEX-END:STORY_FIRESTORE_METHODS

  // CODEX-BEGIN:CHAT_FIRESTORE_METHODS
  Future<SafeResult<DiscoverUsersPage>> fetchDiscoverUsers({
    required String currentUid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    return safeRequest<DiscoverUsersPage>(() async {
      Query<Map<String, dynamic>> query = _firestore
          .collection('users')
          .orderBy('followers', descending: true)
          .limit(limit + 1);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final docs = snapshot.docs;
      final filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in docs) {
        if (doc.id == currentUid) {
          continue;
        }
        filtered.add(doc);
        if (filtered.length == limit) {
          break;
        }
      }
      final users = filtered.map(DiscoverUser.fromDocument).toList();
      final lastDoc = docs.isNotEmpty ? docs.last : startAfter;
      final hasMore = docs.length == limit + 1 || filtered.length == limit;
      return DiscoverUsersPage(
        users: users,
        lastDocument: lastDoc,
        hasMore: hasMore,
      );
    }, debugLabel: 'fetchDiscoverUsers');
  }

  Future<SafeResult<InboxThreadsPage>> fetchInboxThreads({
    required String currentUid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    return safeRequest<InboxThreadsPage>(() async {
      Query<Map<String, dynamic>> query = _firestore
          .collection('dm_threads')
          .where('members', arrayContains: currentUid)
          .orderBy('updatedAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      final snapshot = await query.get();
      final docs = snapshot.docs;
      final threads = docs.map(InboxThreadItem.fromDocument).toList();
      final lastDoc = docs.isNotEmpty ? docs.last : startAfter;
      final hasMore = docs.length == limit;
      return InboxThreadsPage(
        threads: threads,
        lastDocument: lastDoc,
        hasMore: hasMore,
      );
    }, debugLabel: 'fetchInboxThreads');
  }

  Future<SafeResult<String>> openOrCreateDirectThread({
    required String currentUid,
    required String otherUid,
  }) {
    return safeRequest<String>(() async {
      if (currentUid == otherUid) {
        throw ArgumentError('Cannot start DM with yourself');
      }
      final List<String> participants = <String>[currentUid, otherUid]..sort();
      final String threadId = participants.join('_');
      final DocumentReference<Map<String, dynamic>> docRef =
          _firestore.collection('dm_threads').doc(threadId);
      return _firestore.runTransaction<String>((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          transaction.set(
            docRef,
            <String, dynamic>{
              'members': participants,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'lastMessage': null,
              'unread': <String, int>{
                for (final member in participants) member: 0,
              },
            },
            SetOptions(merge: true),
          );
        } else {
          final data = snapshot.data() ?? <String, dynamic>{};
          final storedMembers =
              List<String>.from((data['members'] ?? const <String>[]).cast<String>());
          if (storedMembers.length != 2 ||
              !storedMembers.contains(currentUid) ||
              !storedMembers.contains(otherUid)) {
            transaction.set(
              docRef,
              <String, dynamic>{'members': participants},
              SetOptions(merge: true),
            );
          }
        }
        return threadId;
      });
    }, debugLabel: 'openOrCreateDirectThread');
  }
  // CODEX-END:CHAT_FIRESTORE_METHODS
}
// CODEX-END:STORE_FIRESTORE_SERVICE
