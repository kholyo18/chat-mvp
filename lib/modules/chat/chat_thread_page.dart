import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../calls/agora_call_client.dart';
import '../calls/dm_call_models.dart';
import '../../modules/calls/dm_call_service.dart';
import '../../modules/privacy/privacy_controller.dart';
import '../../services/firestore_service.dart';
import '../translator/translator_service.dart';
import 'chat_message.dart';
import 'chat_thread_controller.dart';

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({super.key, required this.threadId, this.otherUid});

  final String threadId;
  final String? otherUid;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  ChatThreadController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      final translator = context.read<TranslatorService>();
      _controller = ChatThreadController(
        threadId: widget.threadId,
        translatorService: translator,
      )..load();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final readReceipts =
        context.watch<PrivacySettingsController>().settings?.readReceipts ?? true;
    controller.setReadReceipts(readReceipts);
    return ChangeNotifierProvider<ChatThreadController>.value(
      value: controller,
      child: _ChatThreadView(threadId: widget.threadId),
    );
  }
}

class _ChatThreadView extends StatelessWidget {
  const _ChatThreadView({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const ui.TextDirection threadDirection = ui.TextDirection.rtl;
    return Directionality(
      textDirection: threadDirection,
      child: Scaffold(
        appBar: _ChatAppBar(threadId: threadId),
        body: SafeArea(
          child: Stack(
            children: [
              const Column(
                children: [
                  Expanded(child: _MessagesList()),
                  _TypingBanner(),
                  _ReplyPreview(),
                  _Composer(),
                ],
              ),
              _MiniCallOverlay(threadId: threadId),
            ],
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
      ),
    );
  }
}

class _MiniCallOverlay extends StatelessWidget {
  const _MiniCallOverlay({required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context) {
    final callService = DmCallService.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: callService.isMinimized,
      builder: (context, minimized, _) {
        if (!minimized) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<DmCallSession?>(
          valueListenable: callService.activeSession,
          builder: (context, session, __) {
            if (session == null || session.threadId != threadId) {
              return const SizedBox.shrink();
            }
            return PositionedDirectional(
              bottom: 16,
              start: 16,
              end: 16,
              child: _MiniCallCard(session: session),
            );
          },
        );
      },
    );
  }
}

class _MiniCallCard extends StatelessWidget {
  const _MiniCallCard({required this.session});

  final DmCallSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callService = DmCallService.instance;
    final remote = session.otherParticipant ??
        session.caller ??
        session.callee ??
        (session.participants.isNotEmpty ? session.participants.first : null);
    final avatarUrl = remote?.avatarUrl;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      color: theme.colorScheme.surface.withOpacity(0.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.surfaceVariant,
              backgroundImage:
                  avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
              child: avatarUrl == null
                  ? Icon(Icons.person,
                      color: theme.colorScheme.onSurfaceVariant)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    remote?.displayName ?? 'مكالمة جارية',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<DmCallStatus>(
                    valueListenable: callService.callStatus,
                    builder: (context, status, _) {
                      return ValueListenableBuilder<String?>(
                        valueListenable: callService.callStatusMessage,
                        builder: (context, message, __) {
                          final baseLabel = callService.statusLabelFor(
                            status,
                            message: message,
                          );
                          final label =
                              status == DmCallStatus.error ? 'خطأ: $baseLabel' : baseLabel;
                          return Text(
                            label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  _MiniNetworkIndicator(
                    qualityListenable: callService.networkQuality,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.open_in_full_rounded),
              color: theme.colorScheme.primary,
              tooltip: 'عرض المكالمة',
              onPressed: () {
                callService.restoreCallUI();
                unawaited(callService.reopenActiveCallUI());
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.call_end_rounded),
              color: theme.colorScheme.error,
              tooltip: 'إنهاء المكالمة',
              onPressed: () {
                unawaited(callService.terminateCall(session));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniNetworkIndicator extends StatelessWidget {
  const _MiniNetworkIndicator({required this.qualityListenable});

  final ValueListenable<CallNetworkQuality> qualityListenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<CallNetworkQuality>(
      valueListenable: qualityListenable,
      builder: (context, quality, _) {
        final data = _MiniQualityData.fromQuality(quality);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, size: 16, color: data.color),
            const SizedBox(width: 4),
            Text(
              data.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: data.color,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MiniQualityData {
  const _MiniQualityData(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;

  static _MiniQualityData fromQuality(CallNetworkQuality quality) {
    switch (quality) {
      case CallNetworkQuality.excellent:
        return _MiniQualityData(
          'ممتاز',
          Icons.signal_cellular_4_bar,
          Colors.green,
        );
      case CallNetworkQuality.good:
        return _MiniQualityData(
          'جيد',
          Icons.network_wifi,
          Colors.lightGreen,
        );
      case CallNetworkQuality.moderate:
        return _MiniQualityData(
          'متوسط',
          Icons.network_cell,
          Colors.orange,
        );
      case CallNetworkQuality.poor:
        return _MiniQualityData(
          'ضعيف',
          Icons.network_check,
          Colors.deepOrange,
        );
      case CallNetworkQuality.bad:
        return _MiniQualityData(
          'سيئ',
          Icons.signal_cellular_connected_no_internet_4_bar,
          Colors.red,
        );
      case CallNetworkQuality.unknown:
      default:
        return _MiniQualityData(
          'غير معروف',
          Icons.signal_cellular_null,
          Colors.grey,
        );
    }
  }
}

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChatAppBar({required this.threadId});

  final String threadId;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      leading: const BackButton(),
      titleSpacing: 0,
      title: Consumer<ChatThreadController>(
        builder: (context, controller, _) {
          final profile = controller.otherUserProfile;
          final name = profile?.displayName.isNotEmpty == true
              ? profile!.displayName
              : controller.otherUid ?? '...';
          final presenceText = controller.isOtherTyping
              ? 'يكتب الآن…'
              : controller.presenceState.description();
          final avatarUrl = profile?.photoURL;
          return Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.surfaceVariant,
                backgroundImage:
                    avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      presenceText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: () => _startCall(context, isVideo: false),
          tooltip: 'مكالمة صوتية',
        ),
        IconButton(
          icon: const Icon(Icons.videocam_rounded),
          onPressed: () => _startCall(context, isVideo: true),
          tooltip: 'مكالمة فيديو',
        ),
        PopupMenuButton<String>(
          onSelected: (value) => _handleMenuSelection(context, value),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'profile', child: Text('عرض الملف الشخصي')),
            PopupMenuItem(value: 'mute', child: Text('كتم الإشعارات')),
            PopupMenuItem(value: 'clear', child: Text('مسح المحادثة')),
            PopupMenuItem(value: 'report', child: Text('الإبلاغ')),
          ],
        ),
      ],
    );
  }

  void _handleMenuSelection(BuildContext context, String value) {
    final controller = context.read<ChatThreadController>();
    final other = controller.otherUid;
    final messenger = ScaffoldMessenger.of(context);
    switch (value) {
      case 'profile':
        if (other != null) {
          messenger.showSnackBar(
            SnackBar(content: Text('افتح الملف من صفحة المستخدم: $other')),
          );
        } else {
          messenger.showSnackBar(const SnackBar(content: Text('لا يمكن فتح الملف حالياً')));
        }
        break;
      case 'mute':
      case 'clear':
      case 'report':
        messenger.showSnackBar(
          SnackBar(content: Text('الميزة ستتوفر قريباً ($value)')),
        );
        break;
    }
  }
  static final DmCallService _callService = DmCallService.instance;

  Future<void> _startCall(BuildContext context, {required bool isVideo}) async {
    final controller = context.read<ChatThreadController>();
    final otherUid = controller.otherUid;
    if (otherUid == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('فشل بدء المكالمة، حاول مجددًا')),
      );
      return;
    }
    try {
      if (isVideo) {
        await _callService.startVideoCall(
          threadId,
          otherUid,
        );
      } else {
        await _callService.startVoiceCall(
          threadId,
          otherUid,
        );
      }
    } on AgoraPermissionException catch (err, stack) {
      debugPrint(
        'Failed to start DM call due to permissions: missing=${err.missingPermissions}',
      );
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    } catch (err, stack) {
      debugPrint('Failed to start DM call: $err');
      FlutterError.reportError(
        FlutterErrorDetails(exception: err, stack: stack),
      );
    }
  }
}

class _MessagesList extends StatefulWidget {
  const _MessagesList();

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  final ScrollController _scrollController = ScrollController();
  List<String> _knownMessageIds = <String>[];
  bool _initialLoadDone = false;
  Set<String> _lastSeenRequestIds = <String>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _setsAreEqual(Set<String> a, Set<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final value in a) {
      if (!b.contains(value)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _playReceiveFeedback() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (err) {
      if (kDebugMode) {
        debugPrint('Receive sound failed: $err');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatThreadController>();
    final me = controller.currentUid ?? FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<List<ChatMessage>>(
      stream: controller.messagesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data!
            .where((m) => me == null ? true : !m.isHiddenFor(me))
            .toList();
        messages.sort(
          (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        );
        final currentIds = messages.map((m) => m.id).toList();
        final previousIds = _knownMessageIds.toSet();
        final newMessages = messages.where((m) => !previousIds.contains(m.id)).toList();
        final undelivered = me == null
            ? const <ChatMessage>[]
            : messages
                .where((m) => m.senderId != me && m.deliveredAt == null)
                .toList();
        final unseenIds = me == null
            ? <String>{}
            : messages
                .where((m) => m.senderId != me && m.seenAt == null)
                .map((m) => m.id)
                .toSet();
        final wasInitialLoad = !_initialLoadDone;
        if (me != null && undelivered.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(controller.markMessagesAsDelivered(undelivered));
          });
        }
        if (me != null) {
          if (unseenIds.isNotEmpty && !_setsAreEqual(unseenIds, _lastSeenRequestIds)) {
            _lastSeenRequestIds = Set<String>.from(unseenIds);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(controller.markMessagesAsSeen(me));
            });
          } else if (unseenIds.isEmpty && _lastSeenRequestIds.isNotEmpty) {
            _lastSeenRequestIds = <String>{};
          }
        }
        if (!wasInitialLoad && me != null) {
          final newIncoming = newMessages.where((m) => m.senderId != me).toList();
          if (newIncoming.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_playReceiveFeedback());
            });
          }
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _knownMessageIds = currentIds;
          _initialLoadDone = true;
        });
        final entries = _buildEntries(messages);
        return ListView.builder(
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[entries.length - 1 - index];
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offsetAnimation, child: child),
                );
              },
              child: Column(
                key: ValueKey<String>(entry.message.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (entry.dateLabel != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(entry.dateLabel!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ),
                      ),
                    ),
                  _MessageBubble(message: entry.message, isMine: entry.message.senderId == me),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<_MessageEntry> _buildEntries(List<ChatMessage> messages) {
    final entries = <_MessageEntry>[];
    DateTime? lastDay;
    for (final message in messages) {
      final created = message.createdAt ?? DateTime.now();
      final day = DateTime(created.year, created.month, created.day);
      String? label;
      if (lastDay == null || day.difference(lastDay!).inDays != 0) {
        label = _dateLabel(day);
        lastDay = day;
      }
      entries.add(_MessageEntry(message: message, dateLabel: label));
    }
    return entries;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, DateTime(now.year, now.month, now.day))) {
      return 'اليوم';
    }
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    if (_isSameDay(date, yesterday)) {
      return 'أمس';
    }
    final formatter = DateFormat('d MMMM yyyy', 'ar');
    return formatter.format(date);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _MessageEntry {
  const _MessageEntry({required this.message, this.dateLabel});

  final ChatMessage message;
  final String? dateLabel;
}

enum _DeliveryState { none, sent, delivered, seen }

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ChatThreadController>();
    final theme = Theme.of(context);
    final bubbleColor = isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceVariant;
    final textColor = isMine ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 6),
      bottomRight: Radius.circular(isMine ? 6 : 18),
    );
    final timestamp = message.sentAt ?? message.createdAt ?? DateTime.now();
    final time = DateFormat('HH:mm').format(timestamp);
    final translated = controller.translatedTextFor(message.id);
    final deliveryState = _deliveryStateFor(message);
    final statusIcon = _iconForDeliveryState(deliveryState);
    final statusColor = _statusColorForDeliveryState(theme, deliveryState);
    Widget content;

    if (message.deletedForEveryone) {
      content = Text(
        'تم حذف هذه الرسالة',
        style: TextStyle(color: textColor.withOpacity(0.75), fontStyle: FontStyle.italic),
      );
    } else {
      switch (message.type) {
        case ChatMessageType.text:
          content = SelectableText(
            message.text ?? '',
            style: TextStyle(color: textColor, height: 1.4),
          );
          break;
        case ChatMessageType.image:
          content = _MediaPreview(
            messageId: message.id,
            url: message.mediaUrl,
            thumbnailUrl: message.mediaThumbUrl,
            isVideo: false,
          );
          break;
        case ChatMessageType.video:
          content = _MediaPreview(
            messageId: message.id,
            url: message.mediaUrl,
            thumbnailUrl: message.mediaThumbUrl,
            isVideo: true,
          );
          break;
        case ChatMessageType.audio:
          content = _AudioMessageBubble(
            url: message.mediaUrl,
            isMine: isMine,
            duration: _readDuration(message.metadata),
          );
          break;
        case ChatMessageType.file:
          content = _FileAttachment(message: message, isMine: isMine);
          break;
        case ChatMessageType.system:
          content = Text(
            message.text ?? '',
            style: TextStyle(color: textColor.withOpacity(0.75)),
          );
          break;
      }
    }

    final reply = controller.messageById(message.replyToMessageId);
    final forwarded = message.forwardFromThreadId != null;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(context, message, isMine),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
              maxWidth: math.min(MediaQuery.of(context).size.width * 0.8, 360)),
          decoration: BoxDecoration(color: bubbleColor, borderRadius: borderRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (forwarded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'معاد توجيهها',
                    style: TextStyle(
                      color: textColor.withOpacity(0.8),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bubbleColor.withOpacity(isMine ? 0.3 : 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _replyPreview(reply),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 12),
                  ),
                ),
              content,
              if (translated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    translated,
                    style: TextStyle(
                      color: textColor.withOpacity(0.85),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 11),
                  ),
                  if (isMine)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          statusIcon,
                          key: ValueKey<_DeliveryState>(deliveryState),
                          size: 16,
                          color: statusColor,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration? _readDuration(Map<String, dynamic>? metadata) {
    final raw = metadata?['durationMs'];
    if (raw is int) {
      return Duration(milliseconds: raw);
    }
    if (raw is double) {
      return Duration(milliseconds: raw.toInt());
    }
    return null;
  }

  String _replyPreview(ChatMessage message) {
    if (message.deletedForEveryone) {
      return 'تم حذف هذه الرسالة';
    }
    switch (message.type) {
      case ChatMessageType.text:
        return message.text ?? '';
      case ChatMessageType.image:
        return '📷 صورة';
      case ChatMessageType.video:
        return '🎬 فيديو';
      case ChatMessageType.audio:
        return '🎙️ رسالة صوتية';
      case ChatMessageType.file:
        return '📎 ملف';
      case ChatMessageType.system:
        return message.text ?? '';
    }
  }

  _DeliveryState _deliveryStateFor(ChatMessage message) {
    final normalized = message.status?.toLowerCase();
    if (message.seenAt != null || normalized == 'seen') {
      return _DeliveryState.seen;
    }
    if (message.deliveredAt != null || normalized == 'delivered') {
      return _DeliveryState.delivered;
    }
    if (message.sentAt != null || normalized == 'sent') {
      return _DeliveryState.sent;
    }
    return _DeliveryState.none;
  }

  IconData _iconForDeliveryState(_DeliveryState state) {
    switch (state) {
      case _DeliveryState.seen:
      case _DeliveryState.delivered:
        return Icons.done_all_rounded;
      case _DeliveryState.sent:
      case _DeliveryState.none:
        return Icons.check_rounded;
    }
  }

  Color _statusColorForDeliveryState(ThemeData theme, _DeliveryState state) {
    final onBubble = isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    switch (state) {
      case _DeliveryState.seen:
        final accent = theme.colorScheme.secondary;
        return accent;
      case _DeliveryState.delivered:
        return onBubble.withOpacity(0.8);
      case _DeliveryState.sent:
      case _DeliveryState.none:
        return onBubble.withOpacity(0.6);
    }
  }
}

void _showMessageActions(BuildContext context, ChatMessage message, bool isMine) async {
  final controller = context.read<ChatThreadController>();
  final List<_MessageActionItem> actions = <_MessageActionItem>[
    _MessageActionItem('reply', 'رد', Icons.reply_rounded),
    _MessageActionItem('forward', 'إعادة توجيه', Icons.forward_to_inbox_rounded),
    if (message.text != null && message.text!.isNotEmpty)
      _MessageActionItem('copy', 'نسخ', Icons.copy_rounded),
    if (message.text != null && message.text!.isNotEmpty)
      _MessageActionItem('translate', 'ترجمة', Icons.translate_rounded),
    if (isMine) _MessageActionItem('delete-all', 'حذف للجميع', Icons.delete_forever_rounded),
    _MessageActionItem('delete-me', 'حذف عندي فقط', Icons.delete_outline_rounded),
  ];

  final selection = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ...actions.map(
            (action) => ListTile(
              leading: Icon(action.icon),
              title: Text(action.label),
              onTap: () => Navigator.of(context).pop(action.value),
            ),
          ),
        ],
      ),
    ),
  );

  if (selection == null) {
    return;
  }

  try {
    switch (selection) {
      case 'reply':
        unawaited(controller.setReplyTo(message));
        break;
      case 'forward':
        await _showForwardPicker(context, controller, message);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text ?? ''));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم نسخ الرسالة')));
        break;
      case 'translate':
        await controller.translateMessage(message);
        break;
      case 'delete-all':
        await controller.deleteForEveryone(message);
        break;
      case 'delete-me':
        await controller.deleteForMe(message);
        break;
    }
  } catch (err) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعذر تنفيذ العملية: $err')),
    );
  }
}

Future<void> _showForwardPicker(
  BuildContext context,
  ChatThreadController controller,
  ChatMessage message,
) async {
  final me = controller.currentUid ?? FirebaseAuth.instance.currentUser?.uid;
  if (me == null) {
    return;
  }
  final service = FirestoreService();
  final result = await service.fetchInboxThreads(currentUid: me, limit: 20);
  if (result is SafeFailure<InboxThreadsPage>) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    return;
  }
  if (result is! SafeSuccess<InboxThreadsPage>) {
    return;
  }
  final page = result.value;
  final threadId = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text('إرسال إلى محادثة أخرى',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (page.threads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد محادثات أخرى حالياً'),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: page.threads.length,
                itemBuilder: (context, index) {
                  final thread = page.threads[index];
                  final other = thread.members.firstWhere(
                    (m) => m != me,
                    orElse: () => thread.id,
                  );
                  final subtitle = thread.lastMessage ?? '';
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(other, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.of(context).pop(thread.id),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (threadId == null) {
    return;
  }
  await controller.forwardMessage(message, threadId);
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('تمت إعادة التوجيه')));
}

class _TypingBanner extends StatelessWidget {
  const _TypingBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatThreadController>(
      builder: (context, controller, _) {
        if (!controller.isOtherTyping) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: const Text('يكتب الآن…', style: TextStyle(fontSize: 12)),
        );
      },
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatThreadController>(
      builder: (context, controller, child) {
        final message = controller.replyTo;
        if (message == null) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.reply_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _replyPreview(message),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => controller.setReplyTo(null),
              ),
            ],
          ),
        );
      },
    );
  }

  String _replyPreview(ChatMessage message) {
    if (message.deletedForEveryone) {
      return 'تم حذف هذه الرسالة';
    }
    switch (message.type) {
      case ChatMessageType.text:
        return message.text ?? '';
      case ChatMessageType.image:
        return '📷 صورة';
      case ChatMessageType.video:
        return '🎬 فيديو';
      case ChatMessageType.audio:
        return '🎙️ رسالة صوتية';
      case ChatMessageType.file:
        return '📎 ملف';
      case ChatMessageType.system:
        return message.text ?? '';
    }
  }
}

class _Composer extends StatefulWidget {
  const _Composer();

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    final controller = context.read<ChatThreadController>();
    unawaited(controller.updateTyping(false));
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_showSend != hasText) {
      setState(() => _showSend = hasText);
    }
    final controller = context.read<ChatThreadController>();
    unawaited(controller.updateTyping(hasText));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatThreadController>();
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.isUploading)
          const LinearProgressIndicator(minHeight: 2),
        if (controller.isRecording)
          Container(
            width: double.infinity,
            color: theme.colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.mic, color: Colors.redAccent),
                const SizedBox(width: 12),
                Text(_formatDuration(controller.recordingDuration)),
                const Spacer(),
                TextButton(
                  onPressed: () => controller.cancelRecording(),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined),
                onPressed: () => _showEmojiStub(context),
              ),
              IconButton(
                icon: const Icon(Icons.attach_file_rounded),
                onPressed: () => _showAttachmentSheet(context),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: 4,
                    minLines: 1,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة…',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_showSend)
                FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () async {
                    final text = _controller.text;
                    _controller.clear();
                    try {
                      await controller.sendTextMessage(text);
                    } catch (err) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('تعذر إرسال الرسالة: $err')));
                    }
                  },
                  child: const Icon(Icons.send_rounded),
                )
              else
                GestureDetector(
                  onLongPressStart: (_) async {
                    try {
                      await controller.startRecording();
                    } catch (err) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر بدء التسجيل: $err')),
                      );
                    }
                  },
                  onLongPressEnd: (_) async {
                    try {
                      await controller.stopRecordingAndSend();
                    } catch (err) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('تعذر إرسال التسجيل: $err')));
                    }
                  },
                  onLongPressCancel: () => unawaited(controller.cancelRecording()),
                  child: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary,
                    child: const Icon(Icons.mic, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAttachmentSheet(BuildContext context) async {
    final controller = context.read<ChatThreadController>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('صورة / فيديو من المعرض'),
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  await controller.pickFromGallery();
                } catch (err) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('تعذر اختيار ملف: $err')));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('الكاميرا'),
              onTap: () async {
                Navigator.of(context).pop();
                try {
                  await controller.captureFromCamera();
                } catch (err) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('تعذر فتح الكاميرا: $err')));
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showEmojiStub(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.emoji_emotions_outlined, size: 48),
              SizedBox(height: 12),
              Text('لوحة الإيموجي ستتوفر قريباً!')
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({
    required this.messageId,
    required this.url,
    this.thumbnailUrl,
    required this.isVideo,
  });

  final String messageId;
  final String? url;
  final String? thumbnailUrl;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Text(
        'لا يمكن عرض الملف',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
      );
    }
    final heroTag = 'chat-media-$messageId';
    final border = BorderRadius.circular(18);
    final previewUrl = (thumbnailUrl?.isNotEmpty ?? false) ? thumbnailUrl! : url!;
    final aspectRatio = isVideo ? 16 / 9 : 4 / 5;
    return GestureDetector(
      onTap: () => _openViewer(context, heroTag),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: border,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: aspectRatio,
                child: CachedNetworkImage(
                  imageUrl: previewUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, _) =>
                      Container(color: Theme.of(context).colorScheme.surfaceVariant),
                  errorWidget: (context, _, __) => Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image, color: Colors.white70, size: 36),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(isVideo ? 0.35 : 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              if (isVideo)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, String heroTag) {
    final mediaUrl = url;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withOpacity(0.9),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _MediaViewerPage(
              url: mediaUrl,
              heroTag: heroTag,
              isVideo: isVideo,
              thumbnailUrl: thumbnailUrl,
            ),
          );
        },
      ),
    );
  }
}

class _MediaViewerPage extends StatelessWidget {
  const _MediaViewerPage({
    required this.url,
    required this.heroTag,
    required this.isVideo,
    this.thumbnailUrl,
  });

  final String url;
  final String heroTag;
  final bool isVideo;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: heroTag,
              child: isVideo
                  ? _VideoPlayerView(url: url, thumbnailUrl: thumbnailUrl)
                  : InteractiveViewer(
                      maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.contain,
                        placeholder: (context, _) => const Center(
                          child: CircularProgressIndicator(color: Colors.white70),
                        ),
                        errorWidget: (context, _, __) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 72,
                        ),
                      ),
                    ),
            ),
          ),
          PositionedDirectional(
            top: mediaQuery.padding.top + 12,
            start: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'إغلاق',
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _controller;
  Future<void>? _initialization;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.network(widget.url);
    _initialization = _controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
      _controller
        ..setLooping(true)
        ..play();
    }).catchError((Object error, StackTrace stack) {
      if (kDebugMode) {
        debugPrint('Failed to initialize video: $error');
      }
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildPlaceholder(
        const Icon(Icons.error_outline, color: Colors.white70, size: 48),
      );
    }
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildPlaceholder(
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          );
        }
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _controller,
          builder: (context, value, child) {
            final aspect = value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio;
            return GestureDetector(
              onTap: () {
                if (value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: aspect,
                    child: VideoPlayer(_controller),
                  ),
                  AnimatedOpacity(
                    opacity: value.isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 72,
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 16,
                    start: 24,
                    end: 24,
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        backgroundColor: Colors.white24,
                        bufferedColor: Colors.white38,
                        playedColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPlaceholder(Widget child) {
    final previewUrl = widget.thumbnailUrl;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (previewUrl != null && previewUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: previewUrl,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(color: Colors.black26),
              errorWidget: (context, _, __) => Container(color: Colors.black26),
            )
          else
            Container(color: Colors.black26),
          child,
        ],
      ),
    );
  }
}

class _FileAttachment extends StatelessWidget {
  const _FileAttachment({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final name = message.metadata?['name']?.toString() ?? 'ملف مرفق';
    final size = message.metadata?['size'];
    final sizeText = size is num ? _formatBytes(size.toInt()) : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_rounded,
            color: isMine ? Colors.white : Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$name $sizeText',
            style: TextStyle(color: isMine ? Colors.white : Theme.of(context).colorScheme.onSurface),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value > 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '(${value.toStringAsFixed(1)} ${units[unit]})';
  }
}

class _AudioMessageBubble extends StatefulWidget {
  const _AudioMessageBubble({required this.url, required this.isMine, this.duration});

  final String? url;
  final bool isMine;
  final Duration? duration;

  @override
  State<_AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<_AudioMessageBubble> {
  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _duration = widget.duration ?? Duration.zero;
    _player.onPlayerStateChanged.listen((state) {
      setState(() => _state = state);
    });
    _player.onDurationChanged.listen((duration) {
      setState(() => _duration = duration);
    });
    _player.onPositionChanged.listen((position) {
      setState(() => _position = position);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.url;
    if (url == null) {
      return;
    }
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.stop();
      await _player.play(UrlSource(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final maxSeconds = _duration.inSeconds.clamp(1, 3600);
    final progress = maxSeconds == 0 ? 0.0 : _position.inSeconds / maxSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
              color: Colors.white,
              onPressed: _toggle,
            ),
            Text(_formatDuration(_position), style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 8),
            Text(_formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
        Slider(
          value: progress.clamp(0, 1),
          onChanged: (value) {
            final seekTo = Duration(seconds: (value * maxSeconds).toInt());
            _player.seek(seekTo);
          },
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MessageActionItem {
  const _MessageActionItem(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}
