import 'package:flutter/material.dart';

import '../../modules/vip/vip_style.dart';

class VipEntryOverlay extends StatefulWidget {
  const VipEntryOverlay({
    super.key,
    required this.userName,
    required this.style,
    this.duration = const Duration(seconds: 2),
  });

  final String userName;
  final VipStyle style;
  final Duration duration;

  @override
  State<VipEntryOverlay> createState() => _VipEntryOverlayState();
}

class _VipEntryOverlayState extends State<VipEntryOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _controller,
          curve: Curves.easeOut,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.black.withOpacity(0.7),
              boxShadow: widget.style.glowColor != null
                  ? [
                      BoxShadow(
                        color: widget.style.glowColor!,
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconForEffect(widget.style.entryEffectKey),
                    color: widget.style.nameColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  '${widget.userName} joined the chat',
                  style: TextStyle(
                    color: widget.style.nameColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForEffect(String key) {
    switch (key) {
      case 'gold':
        return Icons.star_rounded;
      case 'diamond':
        return Icons.auto_awesome_rounded;
      case 'platinum':
        return Icons.flash_on_rounded;
      default:
        return Icons.bolt;
    }
  }
}
