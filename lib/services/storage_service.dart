// CODEX-BEGIN:STORY_STORAGE_SERVICE
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'firestore_service.dart';

class StorageService {
  StorageService({FirebaseStorage? storage, DateTime Function()? clock})
      : _storage = storage ?? FirebaseStorage.instance,
        _clock = clock ?? DateTime.now;

  final FirebaseStorage _storage;
  final DateTime Function() _clock;

  Future<SafeResult<String>> uploadStoryMedia({
    required String uid,
    required String fileExtension,
    required Uint8List data,
    String? contentType,
  }) {
    return safeRequest<String>(() async {
      final DateTime now = _clock();
      final String sanitizedExtension =
          fileExtension.startsWith('.') ? fileExtension.substring(1) : fileExtension;
      final String fileName =
          '${now.millisecondsSinceEpoch}.${sanitizedExtension.isEmpty ? 'dat' : sanitizedExtension}';
      final Reference ref =
          _storage.ref().child('stories').child(uid).child(fileName);
      UploadTask task;
      if (contentType != null && contentType.isNotEmpty) {
        task = ref.putData(data, SettableMetadata(contentType: contentType));
      } else {
        task = ref.putData(data);
      }
      final TaskSnapshot snapshot = await task;
      return snapshot.ref.getDownloadURL();
    }, debugLabel: 'uploadStoryMedia');
  }
}
// CODEX-END:STORY_STORAGE_SERVICE
