/// UI widget responsible for rendering a single Reel with playback and interactions.
import 'package:characters/characters.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/reel.dart';
import '../../services/reels_service.dart';

class ReelItem extends StatefulWidget {
  const ReelItem({super.key, required this.reel, required this.service});

  final Reel reel;
  final ReelsService service;

  @override
  State<ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<ReelItem> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  bool _isLiked = false;
  int _likesCount = 0;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    _configureFor(widget.reel);
  }

  @override
  void didUpdateWidget(covariant ReelItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reel.id != widget.reel.id ||
        oldWidget.reel.videoUrl != widget.reel.videoUrl) {
      _configureFor(widget.reel);
    } else {
      _syncLikeState();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _configureFor(Reel reel) {
    _controller?.dispose();
    _controller = VideoPlayerController.networkUrl(Uri.parse(reel.videoUrl))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _initializing = false;
        });
        _controller?.play();
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _initializing = false;
          });
        }
      });
    _initializing = true;
    _syncLikeState();
    _likesCount = reel.likesCount;
  }

  void _syncLikeState() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _isLiked = uid != null && widget.reel.likes.contains(uid);
    _likesCount = widget.reel.likesCount;
  }

  Future<void> _handleToggleLike() async {
    if (_likeBusy) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء تسجيل الدخول للتفاعل مع الريلز.')),
        );
      }
      return;
    }
    setState(() {
      _likeBusy = true;
      if (_isLiked) {
        _likesCount = (_likesCount - 1);
        if (_likesCount < 0) {
          _likesCount = 0;
        }
      } else {
        _likesCount = _likesCount + 1;
      }
      _isLiked = !_isLiked;
    });
    try {
      await widget.service.toggleLike(widget.reel.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        // rollback on error
        if (_isLiked) {
          _likesCount = (_likesCount - 1);
          if (_likesCount < 0) {
            _likesCount = 0;
          }
        } else {
          _likesCount = _likesCount + 1;
        }
        _isLiked = !_isLiked;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حصل خطأ أثناء تحديث الإعجاب: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _likeBusy = false;
        });
      }
    }
  }

  void _handleCommentTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('قسم التعليقات قادم قريباً!')),
    );
  }

  void _handleShareTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('مشاركة الريلز قيد التطوير.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final username = widget.reel.userId.isEmpty
        ? '@user'
        : '@${widget.reel.userId.length > 12 ? widget.reel.userId.substring(0, 12) : widget.reel.userId}';
    return GestureDetector(
      onDoubleTap: _handleToggleLike,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoLayer(),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xAA000000),
                  Color(0x55000000),
                  Color(0x11000000),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 96,
            bottom: 32,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.reel.caption.isEmpty
                      ? 'بدون وصف'
                      : widget.reel.caption,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 20,
            bottom: 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAvatar(username),
                const SizedBox(height: 16),
                _buildIconButton(
                  icon: Icons.favorite,
                  filled: _isLiked,
                  label: _likesCount.toString(),
                  onTap: _handleToggleLike,
                ),
                const SizedBox(height: 12),
                _buildIconButton(
                  icon: Icons.comment_rounded,
                  filled: false,
                  label: widget.reel.commentsCount.toString(),
                  onTap: _handleCommentTap,
                ),
                const SizedBox(height: 12),
                _buildIconButton(
                  icon: Icons.share_rounded,
                  filled: false,
                  label: 'شارك',
                  onTap: _handleShareTap,
                ),
              ],
            ),
          ),
          if (_initializing)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoLayer() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(color: Colors.black);
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _buildAvatar(String username) {
    final initials = username.replaceAll('@', '').trim();
    final String letter = initials.isEmpty ? 'U' : initials.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.white24,
      child: Text(
        letter,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required bool filled,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: filled ? Colors.redAccent : Colors.white,
            size: 32,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
