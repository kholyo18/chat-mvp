// CODEX-BEGIN:STORY_CONTROLLER
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../services/firestore_service.dart';
import 'story_repository.dart';

class StoryController extends ChangeNotifier {
  StoryController({
    required StoryRepository repository,
    DateTime Function()? clock,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now;

  final StoryRepository _repository;
  final DateTime Function() _clock;
  final List<Story> _stories = <Story>[];
  bool _isPosting = false;
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  UnmodifiableListView<Story> get stories => UnmodifiableListView(_stories);
  bool get isPosting => _isPosting;
  Stream<String> get errors => _errorController.stream;

  @override
  void dispose() {
    _errorController.close();
    super.dispose();
  }

  void setStories(List<Story> stories) {
    _stories
      ..clear()
      ..addAll(stories);
    notifyListeners();
  }

  Future<SafeResult<Story>> postTextStory({
    required String uid,
    required String text,
    StoryPrivacy privacy = StoryPrivacy.public,
    String? bgColor,
    List<String>? allowedUids,
  }) {
    final DateTime now = _clock();
    final Story optimistic = Story(
      id: 'local-${now.microsecondsSinceEpoch}',
      uid: uid,
      type: StoryType.text,
      privacy: privacy,
      viewers: 0,
      createdAt: now,
      text: text,
      bgColor: bgColor,
      allowedUids: _normalizeAllowed(privacy, allowedUids),
      isPending: true,
    );
    return _executePost(
      optimistic: optimistic,
      operation: () => _repository.postTextStory(
        uid: uid,
        text: text,
        privacy: privacy,
        bgColor: bgColor,
        allowedUids: allowedUids,
        createdAt: now,
      ),
    );
  }

  Future<SafeResult<Story>> postMediaStory({
    required String uid,
    required StoryType type,
    required Uint8List bytes,
    required String fileExtension,
    StoryPrivacy privacy = StoryPrivacy.public,
    List<String>? allowedUids,
    String? contentType,
  }) {
    assert(type != StoryType.text, 'Use postTextStory for text stories');
    final DateTime now = _clock();
    final Story optimistic = Story(
      id: 'local-${now.microsecondsSinceEpoch}',
      uid: uid,
      type: type,
      privacy: privacy,
      viewers: 0,
      createdAt: now,
      mediaUrl: 'pending://${now.microsecondsSinceEpoch}',
      allowedUids: _normalizeAllowed(privacy, allowedUids),
      isPending: true,
    );
    return _executePost(
      optimistic: optimistic,
      operation: () => _repository.postMediaStory(
        uid: uid,
        type: type,
        bytes: bytes,
        fileExtension: fileExtension,
        privacy: privacy,
        allowedUids: allowedUids,
        createdAt: now,
        contentType: contentType,
      ),
    );
  }

  List<String> _normalizeAllowed(
    StoryPrivacy privacy,
    List<String>? allowedUids,
  ) {
    if (privacy != StoryPrivacy.custom) {
      return const <String>[];
    }
    if (allowedUids == null) {
      return const <String>[];
    }
    return List<String>.unmodifiable(
      allowedUids.where((uid) => uid.isNotEmpty),
    );
  }

  Future<SafeResult<Story>> _executePost({
    required Story optimistic,
    required Future<SafeResult<Story>> Function() operation,
  }) async {
    if (_isPosting) {
      final failure = SafeFailure<Story>(
        error: StateError('story-post-in-progress'),
        stackTrace: StackTrace.current,
        message: 'A story is already being posted.',
      );
      _errorController.add(failure.message);
      return failure;
    }
    _isPosting = true;
    _stories.insert(0, optimistic);
    notifyListeners();
    try {
      final SafeResult<Story> result = await operation();
      _isPosting = false;
      if (result is SafeSuccess<Story>) {
        final Story finalized = result.value.copyWith(isPending: false);
        final int index =
            _stories.indexWhere((story) => story.id == optimistic.id);
        if (index >= 0) {
          _stories[index] = finalized;
        } else {
          _stories.insert(0, finalized);
        }
        notifyListeners();
        return SafeSuccess<Story>(finalized);
      } else if (result is SafeFailure<Story>) {
        _stories.removeWhere((story) => story.id == optimistic.id);
        notifyListeners();
        _errorController.add(result.message);
        return result;
      }
      return result;
    } catch (err, stack) {
      _stories.removeWhere((story) => story.id == optimistic.id);
      _isPosting = false;
      notifyListeners();
      final failure = SafeFailure<Story>(
        error: err,
        stackTrace: stack,
        message: err.toString(),
      );
      _errorController.add(failure.message);
      return failure;
    }
  }
}
// CODEX-END:STORY_CONTROLLER
