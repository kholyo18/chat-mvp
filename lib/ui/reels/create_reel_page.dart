/// Screen allowing the user to pick a video and publish it as a reel.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../services/reels_service.dart';

class CreateReelPage extends StatefulWidget {
  const CreateReelPage({super.key});

  @override
  State<CreateReelPage> createState() => _CreateReelPageState();
}

class _CreateReelPageState extends State<CreateReelPage> {
  final ImagePicker _picker = ImagePicker();
  final ReelsService _service = ReelsService();
  final TextEditingController _captionController = TextEditingController();

  XFile? _pickedFile;
  VideoPlayerController? _videoController;
  bool _uploading = false;

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file == null) {
        return;
      }
      _setVideo(file);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر اختيار الفيديو: $error')),
      );
    }
  }

  void _setVideo(XFile file) {
    _pickedFile = file;
    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(file.path))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
        _videoController?.play();
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل تشغيل الفيديو: $error')),
          );
        }
      });
    setState(() {});
  }

  Future<void> _upload() async {
    if (_pickedFile == null || _uploading) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _uploading = true;
    });
    try {
      await _service.uploadReel(
        file: File(_pickedFile!.path),
        caption: _captionController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نشر الريل بنجاح')), 
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل نشر الريل: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final videoSelected = _pickedFile != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء ريل جديد'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _uploading ? null : _pickVideo,
              child: Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  height: 320,
                  child: videoSelected ? _buildVideoPreview() : _buildPlaceholder(theme),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _captionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'الوصف',
                hintText: 'أضف وصفاً للفيديو',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: videoSelected && !_uploading ? _upload : null,
                icon: _uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(_uploading ? 'جارٍ النشر...' : 'نشر'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceVariant,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.videocam_rounded, size: 64),
            SizedBox(height: 12),
            Text('اختر فيديو من الجهاز'),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 9 / 16
              : controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FloatingActionButton.small(
            heroTag: 'toggle_play',
            onPressed: () {
              if (!controller.value.isInitialized) {
                return;
              }
              setState(() {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              });
            },
            child: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
          ),
        ),
      ],
    );
  }
}
