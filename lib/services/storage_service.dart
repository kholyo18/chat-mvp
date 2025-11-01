// CODEX-BEGIN:STORY_STORAGE_SERVICE
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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

  /// Uploads either the profile or cover image for a user.
  ///
  /// When [isCover] is `true` the file is stored under
  /// `users/{uid}/cover.jpg`, otherwise `users/{uid}/profile.jpg`.
  /// The upload uses a public cache-control header so refreshed images
  /// propagate quickly across clients.
  Future<SafeResult<String>> uploadUserImage({
    required String uid,
    required XFile file,
    required bool isCover,
  }) {
    return safeRequest<String>(() async {
      try {
        final Uint8List bytes = await file.readAsBytes();
        final String? mimeType = await file.mimeType;
        final Reference ref = _storage
            .ref()
            .child('users')
            .child(uid)
            .child(isCover ? 'cover.jpg' : 'profile.jpg');
        final metadata = SettableMetadata(
          cacheControl: 'public,max-age=3600',
          contentType: mimeType ?? 'image/jpeg',
        );
        final TaskSnapshot snapshot = await ref.putData(bytes, metadata);
        return snapshot.ref.getDownloadURL();
      } on FirebaseException catch (err) {
        final message = err.message ?? 'upload_failed';
        throw Exception('تعذر رفع الصورة: $message');
      } on PlatformException catch (err) {
        final message = err.message ?? err.code;
        throw Exception('لم نتمكن من الوصول للملفات: $message');
      }
    }, debugLabel: 'uploadUserImage');
  }
}
// CODEX-END:STORY_STORAGE_SERVICE
