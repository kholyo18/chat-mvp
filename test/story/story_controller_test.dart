// CODEX-BEGIN:STORY_CONTROLLER_TEST
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chat_mvp/modules/story/story_controller.dart';
import 'package:chat_mvp/modules/story/story_repository.dart';
import 'package:chat_mvp/services/firestore_service.dart';

class FakeStoryRepository extends StoryRepository {
  FakeStoryRepository();

  Completer<SafeResult<Story>>? textCompleter;
  Completer<SafeResult<Story>>? mediaCompleter;
  StoryType? lastMediaType;
  Uint8List? lastMediaBytes;
  String? lastFileExtension;
  StoryPrivacy? lastPrivacy;
  List<String>? lastAllowed;
  DateTime? lastCreatedAt;
  String? lastContentType;

  @override
  Future<SafeResult<Story>> postTextStory({
    required String uid,
    required String text,
    StoryPrivacy privacy = StoryPrivacy.public,
    String? bgColor,
    List<String>? allowedUids,
    DateTime? createdAt,
  }) {
    lastPrivacy = privacy;
    lastAllowed = allowedUids;
    lastCreatedAt = createdAt;
    textCompleter ??= Completer<SafeResult<Story>>();
    return textCompleter!.future;
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
  }) {
    lastMediaType = type;
    lastMediaBytes = bytes;
    lastFileExtension = fileExtension;
    lastPrivacy = privacy;
    lastAllowed = allowedUids;
    lastCreatedAt = createdAt;
    lastContentType = contentType;
    mediaCompleter ??= Completer<SafeResult<Story>>();
    return mediaCompleter!.future;
  }

  void completeText(SafeResult<Story> result) {
    textCompleter ??= Completer<SafeResult<Story>>();
    if (!textCompleter!.isCompleted) {
      textCompleter!.complete(result);
    }
  }

  void completeMedia(SafeResult<Story> result) {
    mediaCompleter ??= Completer<SafeResult<Story>>();
    if (!mediaCompleter!.isCompleted) {
      mediaCompleter!.complete(result);
    }
  }

  @override
  Stream<List<Story>> publicStories({int limit = 50}) {
    return const Stream<List<Story>>.empty();
  }

  @override
  Stream<List<Story>> viewerStories({
    required String viewerUid,
    Set<String> contactUids = const <String>{},
    int limit = 100,
  }) {
    return const Stream<List<Story>>.empty();
  }

  @override
  Stream<List<Story>> userStories(String uid) {
    return const Stream<List<Story>>.empty();
  }

  @override
  Stream<bool> hasActiveStory(String uid) {
    return const Stream<bool>.empty();
  }

  @override
  Future<SafeResult<void>> incrementStoryViewers(String storyId) async {
    return const SafeSuccess<void>(null);
  }
}

void main() {
  group('StoryController', () {
    late FakeStoryRepository repository;
    late StoryController controller;
    late List<String> errorMessages;
    late StreamSubscription<String> errorSubscription;
    late DateTime Function() clock;

    setUp(() {
      repository = FakeStoryRepository();
      int tick = 0;
      clock = () {
        tick += 1;
        return DateTime.fromMillisecondsSinceEpoch(1000 * tick);
      };
      controller = StoryController(repository: repository, clock: clock);
      errorMessages = <String>[];
      errorSubscription = controller.errors.listen(errorMessages.add);
    });

    tearDown(() async {
      await errorSubscription.cancel();
      controller.dispose();
    });

    test('adds optimistic story and finalizes on success', () async {
      final future = controller.postTextStory(
        uid: 'user-1',
        text: 'hello',
      );
      expect(controller.stories.length, 1);
      final Story optimistic = controller.stories.first;
      expect(optimistic.isPending, isTrue);
      expect(optimistic.text, 'hello');

      final Story serverStory = Story(
        id: 'story-1',
        uid: 'user-1',
        type: StoryType.text,
        privacy: StoryPrivacy.public,
        viewers: 0,
        createdAt: optimistic.createdAt,
        text: 'hello',
      );
      repository.completeText(SafeSuccess<Story>(serverStory));
      final SafeResult<Story> result = await future;
      expect(result, isA<SafeSuccess<Story>>());
      expect(controller.stories.length, 1);
      final Story finalized = controller.stories.first;
      expect(finalized.id, 'story-1');
      expect(finalized.isPending, isFalse);
    });

    test('removes optimistic story on failure and emits error', () async {
      final future = controller.postTextStory(
        uid: 'user-2',
        text: 'failing story',
      );
      expect(controller.stories, isNotEmpty);

      repository.completeText(
        SafeFailure<Story>(
          error: Exception('upload failed'),
          stackTrace: StackTrace.current,
          message: 'upload failed',
        ),
      );
      final SafeResult<Story> result = await future;
      expect(result, isA<SafeFailure<Story>>());
      expect(controller.stories, isEmpty);
      expect(errorMessages, contains('upload failed'));
    });

    test('throttles duplicate post attempts', () async {
      final future = controller.postTextStory(
        uid: 'user-3',
        text: 'first story',
      );
      expect(controller.stories.length, 1);

      final SafeResult<Story> secondAttempt = await controller.postTextStory(
        uid: 'user-3',
        text: 'second story',
      );
      expect(secondAttempt, isA<SafeFailure<Story>>());
      expect(controller.stories.length, 1);
      expect(errorMessages, contains('A story is already being posted.'));

      repository.completeText(
        SafeSuccess<Story>(
          Story(
            id: 'story-2',
            uid: 'user-3',
            type: StoryType.text,
            privacy: StoryPrivacy.public,
            viewers: 0,
            createdAt: controller.stories.first.createdAt,
            text: 'first story',
          ),
        ),
      );
      await future;
    });

    test('delegates media posting to repository and finalizes', () async {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final future = controller.postMediaStory(
        uid: 'user-4',
        type: StoryType.image,
        bytes: bytes,
        fileExtension: 'jpg',
        privacy: StoryPrivacy.custom,
        allowedUids: <String>['viewer-1', ''],
        contentType: 'image/jpeg',
      );
      expect(controller.stories.length, 1);
      expect(repository.lastMediaType, StoryType.image);
      expect(repository.lastMediaBytes, bytes);
      expect(repository.lastFileExtension, 'jpg');
      expect(repository.lastPrivacy, StoryPrivacy.custom);
      expect(repository.lastAllowed, <String>['viewer-1', '']);
      expect(repository.lastContentType, 'image/jpeg');

      final Story optimistic = controller.stories.first;
      final Story serverStory = Story(
        id: 'story-3',
        uid: 'user-4',
        type: StoryType.image,
        privacy: StoryPrivacy.custom,
        viewers: 0,
        createdAt: optimistic.createdAt,
        mediaUrl: 'https://example.com/story.jpg',
        allowedUids: const <String>['viewer-1'],
      );
      repository.completeMedia(SafeSuccess<Story>(serverStory));
      final SafeResult<Story> result = await future;
      expect(result, isA<SafeSuccess<Story>>());
      final Story finalized = controller.stories.first;
      expect(finalized.mediaUrl, 'https://example.com/story.jpg');
      expect(finalized.isPending, isFalse);
    });
  });
}
// CODEX-END:STORY_CONTROLLER_TEST
