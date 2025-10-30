// CODEX-BEGIN:STORY_REPOSITORY
import 'dart:typed_data';

import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';

abstract class StoryRepository {
  const StoryRepository();

  Future<SafeResult<Story>> postTextStory({
    required String uid,
    required String text,
    StoryPrivacy privacy = StoryPrivacy.public,
    String? bgColor,
    List<String>? allowedUids,
    DateTime? createdAt,
  });

  Future<SafeResult<Story>> postMediaStory({
    required String uid,
    required StoryType type,
    required Uint8List bytes,
    required String fileExtension,
    StoryPrivacy privacy = StoryPrivacy.public,
    List<String>? allowedUids,
    DateTime? createdAt,
    String? contentType,
  });

  Stream<List<Story>> publicStories({int limit = 50});

  Stream<List<Story>> viewerStories({
    required String viewerUid,
    Set<String> contactUids = const <String>{},
    int limit = 100,
  });

  Stream<List<Story>> userStories(String uid);

  Stream<bool> hasActiveStory(String uid);

  Future<SafeResult<void>> incrementStoryViewers(String storyId);
}

class FirestoreStoryRepository extends StoryRepository {
  FirestoreStoryRepository({
    required FirestoreService firestoreService,
    required StorageService storageService,
    DateTime Function()? clock,
  })  : _firestoreService = firestoreService,
        _storageService = storageService,
        _clock = clock ?? DateTime.now;

  final FirestoreService _firestoreService;
  final StorageService _storageService;
  final DateTime Function() _clock;

  List<String>? _sanitizeAllowed(StoryPrivacy privacy, List<String>? allowed) {
    if (privacy != StoryPrivacy.custom) {
      return null;
    }
    if (allowed == null) {
      return <String>[];
    }
    final filtered = allowed.where((uid) => uid.isNotEmpty).toSet().toList();
    return filtered;
  }

  @override
  Future<SafeResult<Story>> postTextStory({
    required String uid,
    required String text,
    StoryPrivacy privacy = StoryPrivacy.public,
    String? bgColor,
    List<String>? allowedUids,
    DateTime? createdAt,
  }) {
    final List<String>? sanitizedAllowed =
        _sanitizeAllowed(privacy, allowedUids);
    return _firestoreService.createStory(
      uid: uid,
      type: StoryType.text,
      privacy: privacy,
      createdAt: createdAt ?? _clock(),
      text: text,
      bgColor: bgColor,
      allowedUids: sanitizedAllowed,
    );
  }

  @override
  Future<SafeResult<Story>> postMediaStory({
    required String uid,
    required StoryType type,
    required Uint8List bytes,
    required String fileExtension,
    StoryPrivacy privacy = StoryPrivacy.public,
    List<String>? allowedUids,
    DateTime? createdAt,
    String? contentType,
  }) async {
    assert(type != StoryType.text, 'Use postTextStory for text stories');
    final List<String>? sanitizedAllowed =
        _sanitizeAllowed(privacy, allowedUids);
    final SafeResult<String> uploadResult = await _storageService
        .uploadStoryMedia(
      uid: uid,
      fileExtension: fileExtension,
      data: bytes,
      contentType: contentType,
    );
    if (uploadResult is SafeFailure<String>) {
      return SafeFailure<Story>(
        error: uploadResult.error,
        stackTrace: uploadResult.stackTrace,
        message: uploadResult.message,
      );
    }
    final String mediaUrl = (uploadResult as SafeSuccess<String>).value;
    return _firestoreService.createStory(
      uid: uid,
      type: type,
      privacy: privacy,
      createdAt: createdAt ?? _clock(),
      mediaUrl: mediaUrl,
      allowedUids: sanitizedAllowed,
    );
  }

  @override
  Stream<List<Story>> publicStories({int limit = 50}) {
    return _firestoreService.latestPublicStories(limit: limit);
  }

  @override
  Stream<List<Story>> viewerStories({
    required String viewerUid,
    Set<String> contactUids = const <String>{},
    int limit = 100,
  }) {
    return _firestoreService.storiesForViewer(
      viewerUid: viewerUid,
      contactUids: contactUids,
      limit: limit,
    );
  }

  @override
  Stream<List<Story>> userStories(String uid) {
    return _firestoreService.storiesForUser(uid);
  }

  @override
  Stream<bool> hasActiveStory(String uid) {
    return _firestoreService.hasActiveStory(uid);
  }

  @override
  Future<SafeResult<void>> incrementStoryViewers(String storyId) {
    return _firestoreService.incrementStoryViewers(storyId);
  }
}
// CODEX-END:STORY_REPOSITORY
