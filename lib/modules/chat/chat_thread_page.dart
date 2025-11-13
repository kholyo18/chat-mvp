import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show TextDirection;

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:characters/characters.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
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
import 'user_opinion_page.dart';
import 'models/ai_insight.dart';
import 'models/typing_preview.dart';
import 'services/typing_preview_service.dart';
import 'widgets/ai_insight_sheet.dart';

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
      final entitlements = context.read<TypingPreviewService>();
      _controller = ChatThreadController(
        threadId: widget.threadId,
        translatorService: translator,
        entitlements: entitlements,
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
        context.watch<PrivacySettingsController>().settings?.readReceipts ??
        true;
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
    final dir = Directionality.of(context);
    return Directionality(
      textDirection: dir,
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
    final remote =
        session.otherParticipant ??
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
              backgroundImage: avatarUrl != null
                  ? CachedNetworkImageProvider(avatarUrl)
                  : null,
              child: avatarUrl == null
                  ? Icon(
                      Icons.person,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
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
                          final label = status == DmCallStatus.error
                              ? 'خطأ: $baseLabel'
                              : baseLabel;
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
              style: theme.textTheme.bodySmall?.copyWith(color: data.color),
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
        return _MiniQualityData('جيد', Icons.network_wifi, Colors.lightGreen);
      case CallNetworkQuality.moderate:
        return _MiniQualityData('متوسط', Icons.network_cell, Colors.orange);
      case CallNetworkQuality.poor:
        return _MiniQualityData('ضعيف', Icons.network_check, Colors.deepOrange);
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
                backgroundImage: avatarUrl != null
                    ? CachedNetworkImageProvider(avatarUrl)
                    : null,
                child: avatarUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
          itemBuilder: (context) {
            final controller = context.read<ChatThreadController>();
            final displayName =
                controller.otherUserProfile?.displayName ?? 'المستخدم';
            final locale = Localizations.maybeLocaleOf(context)?.languageCode;
            final isArabic =
                locale == 'ar' ||
                Directionality.of(context) == TextDirection.rtl;
            final opinionLabel = isArabic
                ? 'نظرتك عن $displayName'
                : 'Your view about $displayName';
            return [
              const PopupMenuItem(
                value: 'profile',
                child: Text('عرض الملف الشخصي'),
              ),
              PopupMenuItem(value: 'opinion', child: Text(opinionLabel)),
              const PopupMenuItem(value: 'mute', child: Text('كتم الإشعارات')),
              const PopupMenuItem(value: 'clear', child: Text('مسح المحادثة')),
              const PopupMenuItem(value: 'report', child: Text('الإبلاغ')),
            ];
          },
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
          messenger.showSnackBar(
            const SnackBar(content: Text('لا يمكن فتح الملف حالياً')),
          );
        }
        break;
      case 'opinion':
        final current = controller.currentUid;
        final profile = controller.otherUserProfile;
        final otherDisplayName = profile?.displayName ?? 'المستخدم';
        if (current == null || other == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('لا يمكن فتح الصفحة حالياً')),
          );
          break;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserOpinionPage(
              currentUid: current,
              otherUid: other,
              displayName: otherDisplayName,
            ),
          ),
        );
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
        await _callService.startVideoCall(threadId, otherUid);
      } else {
        await _callService.startVoiceCall(threadId, otherUid);
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
        final currentIds = messages.map((m) => m.id).toList();
        final previousIds = _knownMessageIds.toSet();
        final newMessages = messages
            .where((m) => !previousIds.contains(m.id))
            .toList();
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
          if (unseenIds.isNotEmpty &&
              !_setsAreEqual(unseenIds, _lastSeenRequestIds)) {
            _lastSeenRequestIds = Set<String>.from(unseenIds);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(controller.markMessagesAsSeen(me));
            });
          } else if (unseenIds.isEmpty && _lastSeenRequestIds.isNotEmpty) {
            _lastSeenRequestIds = <String>{};
          }
        }
        if (!wasInitialLoad && me != null) {
          final newIncoming = newMessages
              .where((m) => m.senderId != me)
              .toList();
          if (newIncoming.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              unawaited(_playReceiveFeedback());
            });
          }
        }
        final shouldScrollToBottom = wasInitialLoad ||
            (me != null && newMessages.any((m) => m.senderId == me));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _knownMessageIds = currentIds;
          _initialLoadDone = true;
          if (shouldScrollToBottom && _scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
        // Temporary diagnostics to verify message visibility. Remove after confirming fix.
        // ignore: avoid_print
        print('Loaded messages: ${messages.length}');
        if (messages.isEmpty) {
          // ignore: avoid_print
          print('Snapshot doc IDs: ${controller.lastSnapshotDocIds}');
        }
        final sortedMessages = List<ChatMessage>.from(messages)
          ..sort((a, b) {
            final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final compare = ta.compareTo(tb);
            if (compare != 0) {
              return compare;
            }
            return a.id.compareTo(b.id);
          });
        final entries = _buildEntries(sortedMessages);
        return ListView.builder(
          controller: _scrollController,
          reverse: false,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final message = entry.message;
            final bool isMine = me != null && message.senderId == me;
            final created =
                message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final id = message.id.isNotEmpty
                ? message.id
                : '${created.millisecondsSinceEpoch}-$index';
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final offsetAnimation =
                    Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              child: Column(
                key: ValueKey<String>('entry-${message.id}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (entry.dateLabel != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            entry.dateLabel!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ),
                  Dismissible(
                    key: ValueKey<String>('msg_$id'),
                    direction: DismissDirection.none,
                    background: Align(
                      alignment: isMine
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.centerEnd,
                      child: const _TrashPill(),
                    ),
                    secondaryBackground: const SizedBox.shrink(),
                    child: Align(
                      key: ValueKey<String>(message.id),
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.78,
                        ),
                        child: _MessageBubble(
                          message: message,
                          isMine: isMine,
                        ),
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

  List<_MessageEntry> _buildEntries(List<ChatMessage> messages) {
    final entries = <_MessageEntry>[];
    DateTime? lastDay;
    for (final message in messages) {
      final created =
          message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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

class _TrashPill extends StatelessWidget {
  const _TrashPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(
        Icons.delete_outline,
        color: theme.colorScheme.onErrorContainer,
        size: 20,
      ),
    );
  }
}

enum _DeliveryState { none, sent, delivered, seen }

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return _MessageBubble(message: message, isMine: isMine);
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  static const double _replyTriggerDy = 96.0;
  static const double _replyVisualLimit = 64.0;
  static const double _insightTriggerDx = 48.0;
  static const double _insightVisualLimit = 60.0;
  static const AiInsight _missingKeyInsight = AiInsight(
    title: 'الميزة غير مفعّلة',
    bullets: ['مطلوب مفتاح OpenAI لتفعيل هذه الميزة.'],
  );
  static const AiInsight _errorInsight = AiInsight(
    title: 'خدمة الذكاء غير متاحة',
    bullets: ['تعذر الحصول على الملخص حاليًا، حاول لاحقًا.'],
  );
  static const AiInsight _invalidKeyInsight = AiInsight(
    title: 'المفتاح غير صالح أو منتهي',
    bullets: ['تحقق من صلاحية مفتاح OpenAI في .env ثم أعد التشغيل.'],
  );
  static const AiInsight _rateLimitInsight = AiInsight(
    title: 'الحدّ اليومي/الدقيقة مستهلك، جرّب لاحقًا',
    bullets: ['انتظر قليلاً قبل إعادة المحاولة.'],
  );
  static const AiInsight _networkInsight = AiInsight(
    title: 'تعذر الاتصال بالخادم، تحقق من الشبكة',
    bullets: ['تحقق من اتصال الإنترنت أو جرّب VPN ثم أعد المحاولة.'],
  );

  double _dragVisualOffset = 0;
  bool _willReply = false;
  bool _hapticPlayed = false;
  double _swipeDragOffset = 0;
  bool _isInDeleteZone = false;
  bool _isHorizontalDragActive = false;
  bool _pendingPermanentRemoval = false;
  double _insightDragExtent = 0;
  bool _insightGestureActive = false;
  bool _insightSheetActive = false;
  TextDirection? _currentTextDirection;

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _swipeDragOffset = 0;
      _isInDeleteZone = false;
      _isHorizontalDragActive = false;
      _pendingPermanentRemoval = false;
      _insightDragExtent = 0;
      _insightGestureActive = false;
    }
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    _resetSwipeState();
    _dragVisualOffset = 0;
    _willReply = false;
    _hapticPlayed = false;
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final downward = math.max(details.offsetFromOrigin.dy, 0);
    final shouldReply = downward > _replyTriggerDy;

    if (shouldReply != _willReply) {
      setState(() {
        _willReply = shouldReply;
      });
      if (shouldReply && !_hapticPlayed) {
        HapticFeedback.mediumImpact();
        _hapticPlayed = true;
      }
      if (!shouldReply) {
        _hapticPlayed = false;
      }
    }

    final double visualOffset = downward
        .clamp(0.0, _replyVisualLimit)
        .toDouble();
    if (visualOffset != _dragVisualOffset) {
      setState(() {
        _dragVisualOffset = visualOffset.toDouble();
      });
    }
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    final shouldReply = _willReply;
    if (!mounted) {
      return;
    }
    _resetDragState();
    if (!mounted) {
      return;
    }

    if (shouldReply) {
      final controller = context.read<ChatThreadController>();
      unawaited(controller.setReplyTo(widget.message));
    } else {
      _showMessageActions(context, widget.message, widget.isMine);
    }
  }

  void _handleLongPressCancel() {
    _resetDragState();
  }

  void _resetDragState() {
    if (!mounted) {
      return;
    }
    if (_dragVisualOffset != 0 || _willReply) {
      setState(() {
        _dragVisualOffset = 0;
        _willReply = false;
      });
    } else {
      _dragVisualOffset = 0;
      _willReply = false;
    }
    _hapticPlayed = false;
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMine = widget.isMine;
    final controller = context.read<ChatThreadController>();
    final theme = Theme.of(context);
    final bubbleColor = isMine
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceVariant;
    final textColor = isMine
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 6),
      bottomRight: Radius.circular(isMine ? 6 : 18),
    );
    final timestamp = message.sentAt ??
        message.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final time = DateFormat('HH:mm').format(timestamp);
    final translated = controller.translatedTextFor(message.id);
    final deliveryState = _deliveryStateFor(message);
    final statusIcon = _iconForDeliveryState(deliveryState);
    final statusColor = _statusColorForDeliveryState(theme, deliveryState);
    Widget content;

    if (message.deletedForEveryone) {
      content = Text(
        'تم حذف هذه الرسالة',
        style: TextStyle(
          color: textColor.withOpacity(0.75),
          fontStyle: FontStyle.italic,
        ),
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
    final canSwipeDelete = _canAttemptSwipeDelete(message);
    final TextDirection textDirection = Directionality.of(context);
    _currentTextDirection = textDirection;
    final bool canUseAiInsight = controller.canUseSwipeAiInsight();

    final bubblePadding = isMine
        ? const EdgeInsets.only(left: 64, right: 8, top: 4, bottom: 4)
        : const EdgeInsets.only(left: 8, right: 64, top: 4, bottom: 4);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: borderRadius,
      ),
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
                style: TextStyle(
                  color: textColor.withOpacity(0.85),
                  fontSize: 12,
                ),
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
                style: TextStyle(
                  color: textColor.withOpacity(0.8),
                  fontSize: 11,
                ),
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
    );

    final translatedBubble = Transform.translate(
      offset: Offset(
        (canSwipeDelete ? _swipeDragOffset : 0) + _insightVisualShift(),
        _dragVisualOffset > 0 ? _dragVisualOffset * 0.25 : 0,
      ),
      child: bubble,
    );

    final animatedBubble = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: 1.0,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: _pendingPermanentRemoval
          ? const SizedBox.shrink(key: ValueKey('removed-bubble'))
          : KeyedSubtree(
              key: ValueKey<String>('bubble-${message.id}'),
              child: translatedBubble,
            ),
    );

    final bubbleStack = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (canSwipeDelete)
          _SwipeDeleteBackground(
            visible: _swipeDragOffset != 0,
            isActive: _isInDeleteZone,
            borderRadius: borderRadius,
            alignment: _swipeBackgroundAlignment(textDirection),
          ),
        if (!canUseAiInsight)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _insightDragExtent > 8 ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Align(
                  alignment: _insightHintAlignment(textDirection),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'ميزة الذكاء الاصطناعي متاحة للحسابات المميزة',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        animatedBubble,
      ],
    );

    final bubbleGesture = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => _showMessageActions(context, message, isMine),
      onLongPressStart: _handleLongPressStart,
      onLongPressMoveUpdate: _handleLongPressMoveUpdate,
      onLongPressEnd: _handleLongPressEnd,
      onLongPressCancel: _handleLongPressCancel,
      onHorizontalDragStart: _handleHorizontalDragStart,
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onHorizontalDragCancel: _handleHorizontalDragCancel,
      child: bubbleStack,
    );

    return Padding(
      padding: bubblePadding,
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      math.min(MediaQuery.of(context).size.width * 0.8, 360),
                ),
                child: bubbleGesture,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canAttemptSwipeDelete(ChatMessage message) {
    return widget.isMine && !message.deletedForEveryone;
  }

  double _insightVisualShift() {
    if (_insightDragExtent == 0) {
      return 0;
    }
    final direction = _currentTextDirection ?? TextDirection.ltr;
    final clamped = math.min(_insightDragExtent, _insightVisualLimit);
    return direction == TextDirection.rtl ? -clamped : clamped;
  }

  AlignmentGeometry _insightHintAlignment(TextDirection direction) {
    return direction == TextDirection.rtl
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
  }

  AlignmentGeometry _swipeBackgroundAlignment(TextDirection direction) {
    // We currently require a swipe towards the center of the conversation,
    // which translates to a leftward drag for outgoing messages.
    return direction == TextDirection.rtl
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd;
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    _insightGestureActive = true;
    _insightDragExtent = 0;
    if (!_canAttemptSwipeDelete(widget.message)) {
      _isHorizontalDragActive = false;
      return;
    }
    _resetSwipeState();
    _isHorizontalDragActive = true;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta == 0 && _isHorizontalDragActive) {
      return;
    }
    if (delta != 0) {
      _updateInsightGesture(delta);
    }
    if (!_canAttemptSwipeDelete(widget.message)) {
      return;
    }
    _isHorizontalDragActive = true;
    final nextOffset = (_swipeDragOffset + delta).clamp(-_maxSwipeExtent(), 0.0);
    final effective = _effectiveSwipeExtent(nextOffset);
    final threshold = _deleteThresholdPx();
    final inDeleteZone = effective >= threshold;
    if (_swipeDragOffset != nextOffset || _isInDeleteZone != inDeleteZone) {
      setState(() {
        _swipeDragOffset = nextOffset;
        _isInDeleteZone = inDeleteZone;
      });
    }
  }

  Future<void> _handleHorizontalDragEnd(DragEndDetails details) async {
    final canDelete = _canAttemptSwipeDelete(widget.message);
    var deleteGestureConsumed = false;
    if (canDelete) {
      final meetsThreshold =
          _isInDeleteZone && _effectiveSwipeExtent(_swipeDragOffset) >= _deleteThresholdPx();
      if (meetsThreshold && !_canUseSwipeDelete()) {
        _showPremiumOnlySnack();
        _resetSwipeState();
        deleteGestureConsumed = true;
      } else if (meetsThreshold) {
        final confirmed = await _showPermanentDeleteConfirmation();
        if (!mounted) {
          return;
        }
        deleteGestureConsumed = true;
        if (confirmed) {
          setState(() {
            _pendingPermanentRemoval = true;
            _swipeDragOffset = 0;
            _isInDeleteZone = false;
            _isHorizontalDragActive = false;
          });
          await _performPermanentDelete();
        } else {
          _resetSwipeState();
        }
      } else {
        _resetSwipeState();
      }
    }
    await _maybeTriggerInsight(deleteActionTriggered: deleteGestureConsumed);
  }

  void _handleHorizontalDragCancel() {
    if (_canAttemptSwipeDelete(widget.message)) {
      _resetSwipeState();
    }
    _resetInsightGesture();
  }

  void _resetSwipeState() {
    if (!mounted) {
      _swipeDragOffset = 0;
      _isInDeleteZone = false;
      _isHorizontalDragActive = false;
      return;
    }
    if (_swipeDragOffset == 0 && !_isInDeleteZone && !_isHorizontalDragActive) {
      return;
    }
    setState(() {
      _swipeDragOffset = 0;
      _isInDeleteZone = false;
      _isHorizontalDragActive = false;
    });
  }

  double _deleteThresholdPx() {
    final availableWidth = math.min(MediaQuery.of(context).size.width * 0.8, 360.0);
    return math.max(availableWidth * 0.28, 90);
  }

  double _maxSwipeExtent() {
    return _deleteThresholdPx() + 72;
  }

  double _effectiveSwipeExtent(double offset) {
    return offset < 0 ? -offset : offset;
  }

  void _updateInsightGesture(double delta) {
    if (!_insightGestureActive || delta == 0) {
      return;
    }
    final direction = _currentTextDirection ?? TextDirection.ltr;
    final adjusted = direction == TextDirection.rtl ? -delta : delta;
    final nextExtent = (_insightDragExtent + adjusted).clamp(0.0, _insightVisualLimit * 2);
    if (nextExtent == _insightDragExtent) {
      return;
    }
    if (!mounted) {
      _insightDragExtent = nextExtent;
      return;
    }
    setState(() {
      _insightDragExtent = nextExtent;
    });
  }

  void _resetInsightGesture() {
    if (_insightDragExtent == 0 && !_insightGestureActive) {
      _insightGestureActive = false;
      return;
    }
    if (!mounted) {
      _insightDragExtent = 0;
      _insightGestureActive = false;
      return;
    }
    setState(() {
      _insightDragExtent = 0;
      _insightGestureActive = false;
    });
  }

  Future<void> _maybeTriggerInsight({required bool deleteActionTriggered}) async {
    if (!mounted) {
      _insightGestureActive = false;
      return;
    }
    final controller = context.read<ChatThreadController>();
    final message = widget.message;
    final bool hasContent = _hasInsightContent(message);
    final bool gestureReachedTrigger = _insightGestureActive &&
        !deleteActionTriggered &&
        _insightDragExtent >= _insightTriggerDx &&
        hasContent;
    final bool featureEnabled = controller.canUseSwipeAiInsight();
    if (gestureReachedTrigger && !featureEnabled) {
      _resetInsightGesture();
      _showAiInsightDisabledToast();
      return;
    }
    final bool shouldTrigger = gestureReachedTrigger && featureEnabled;
    _resetInsightGesture();
    if (!shouldTrigger) {
      return;
    }
    unawaited(_showAiInsightForMessage(controller, message));
  }

  void _showAiInsightDisabledToast() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(content: Text('الميزة غير مفعّلة')),
    );
  }

  void _trackInsightSheet(Future<dynamic> sheetFuture) {
    _insightSheetActive = true;
    sheetFuture.whenComplete(() {
      _insightSheetActive = false;
    });
  }

  bool _hasInsightContent(ChatMessage message) {
    final text = message.text?.trim() ?? '';
    if (text.isNotEmpty) {
      return true;
    }
    return _messageImageUrl(message) != null;
  }

  String? _messageImageUrl(ChatMessage message) {
    if (message.type == ChatMessageType.image) {
      final url = message.mediaUrl;
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  Future<void> _showAiInsightForMessage(
    ChatThreadController controller,
    ChatMessage message, {
    String? localeOverride,
    bool explainMore = false,
    bool translationMode = false,
  }) async {
    if (!mounted) {
      return;
    }
    final aiService = controller.aiInsightService;
    final locale = translationMode
        ? 'en'
        : (localeOverride ?? Localizations.localeOf(context).languageCode);
    final text = message.text;
    final imageUrl = _messageImageUrl(message);

    if (!controller.canUseSwipeAiInsight()) {
      _showAiInsightDisabledToast();
      return;
    }

    final followupInstruction = _buildFollowupInstruction(
      explainMore: explainMore,
      translationMode: translationMode,
      locale: locale,
    );

    final analysisFuture = aiService.analyze(
      userLocale: locale,
      text: text,
      imageUrl: imageUrl,
      followupInstruction: followupInstruction,
    );

    final loadingSheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AiInsightSheet.loading(),
    );
    _trackInsightSheet(loadingSheet);

    AiInsight insight;
    try {
      insight = await analysisFuture;
    } on AiInsightException catch (error) {
      insight = _insightForError(error);
    } on StateError catch (error) {
      if (error.message == 'OPENAI_API_KEY_MISSING') {
        insight = _missingKeyInsight;
      } else {
        insight = _errorInsight;
      }
    } catch (_) {
      insight = _errorInsight;
    }

    if (!mounted || !_insightSheetActive) {
      return;
    }

    final hasCopyableContent = _hasCopyableInsight(insight);
    final hasText = (message.text?.trim().isNotEmpty ?? false);
    final AiInsightSheetAction? translateCallback =
        (translationMode || locale == 'en' || !hasText)
            ? null
            : (BuildContext sheetCtx) =>
                _handleAiTranslate(sheetCtx, controller, message);
    final AiInsightSheetAction explainCallback =
        (BuildContext sheetCtx) =>
            _handleAiExplainMore(sheetCtx, controller, message, locale);
    final AiInsightSheetAction retryCallback = (BuildContext sheetCtx) =>
        _handleAiRetry(
          sheetCtx,
          controller,
          message,
          locale,
          explainMore: explainMore,
          translationMode: translationMode,
        );
    final AiInsightSheetAction? copyCallback = hasCopyableContent
        ? (BuildContext sheetCtx) => _handleAiCopy(sheetCtx, insight)
        : null;

    final replacement = AiInsightSheet.replaceWith(
      context,
      insight,
      onTranslate: translateCallback,
      onExplainMore: explainCallback,
      onCopy: copyCallback,
      onRetry: retryCallback,
    );
    _trackInsightSheet(replacement);
    unawaited(replacement);
  }

  String? _buildFollowupInstruction({
    required bool explainMore,
    required bool translationMode,
    required String locale,
  }) {
    if (translationMode) {
      return 'Translate the message to $locale and fill the translation field with a natural answer.';
    }
    if (explainMore) {
      return 'Explain the message in greater detail and highlight extra helpful context.';
    }
    return null;
  }

  bool _hasCopyableInsight(AiInsight insight) {
    return insight.bullets.isNotEmpty ||
        (insight.answer?.trim().isNotEmpty ?? false) ||
        (insight.translation?.trim().isNotEmpty ?? false) ||
        (insight.imageCaption?.trim().isNotEmpty ?? false) ||
        insight.facts.isNotEmpty;
  }

  void _handleAiTranslate(
    BuildContext sheetContext,
    ChatThreadController controller,
    ChatMessage message,
  ) {
    Navigator.of(sheetContext).maybePop();
    unawaited(
      _showAiInsightForMessage(
        controller,
        message,
        localeOverride: 'en',
        translationMode: true,
      ),
    );
  }

  void _handleAiExplainMore(
    BuildContext sheetContext,
    ChatThreadController controller,
    ChatMessage message,
    String locale,
  ) {
    Navigator.of(sheetContext).maybePop();
    unawaited(
      _showAiInsightForMessage(
        controller,
        message,
        localeOverride: locale,
        explainMore: true,
      ),
    );
  }

  void _handleAiRetry(
    BuildContext sheetContext,
    ChatThreadController controller,
    ChatMessage message,
    String locale, {
    bool explainMore = false,
    bool translationMode = false,
  }) {
    Navigator.of(sheetContext).maybePop();
    unawaited(
      _showAiInsightForMessage(
        controller,
        message,
        localeOverride: locale,
        explainMore: explainMore,
        translationMode: translationMode,
      ),
    );
  }

  Future<void> _handleAiCopy(
    BuildContext sheetContext,
    AiInsight insight,
  ) async {
    final buffer = StringBuffer()
      ..writeln(insight.title);
    if (insight.answer != null && insight.answer!.trim().isNotEmpty) {
      buffer.writeln(insight.answer!.trim());
    }
    for (final bullet in insight.bullets) {
      buffer.writeln('• $bullet');
    }
    if (insight.translation != null && insight.translation!.trim().isNotEmpty) {
      buffer.writeln(insight.translation!.trim());
    }
    if (insight.imageCaption != null && insight.imageCaption!.trim().isNotEmpty) {
      buffer.writeln(insight.imageCaption!.trim());
    }
    for (final fact in insight.facts) {
      buffer.writeln(fact);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    final messenger = ScaffoldMessenger.maybeOf(sheetContext);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(content: Text('تم النسخ إلى الحافظة')),
    );
  }

  AiInsight _insightForError(AiInsightException error) {
    final status = error.statusCode;
    if (status == 401 || status == 403) {
      return _invalidKeyInsight;
    }
    if (status == 429) {
      return _rateLimitInsight;
    }
    if (error.isNetworkError || error.isTimeout) {
      return _networkInsight;
    }
    return _errorInsight;
  }

  bool _canUseSwipeDelete() {
    final typingPreviewService = context.read<TypingPreviewService>();
    return typingPreviewService.canUseSwipePermanentDelete;
  }

  void _showPremiumOnlySnack() {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('ميزة الحذف النهائي متاحة للحسابات المميزة فقط 💎'),
      ),
    );
  }

  Future<bool> _showPermanentDeleteConfirmation() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _PermanentDeleteConfirmationSheet(),
    );
    return result == true;
  }

  Future<void> _performPermanentDelete() async {
    final controller = context.read<ChatThreadController>();
    try {
      await controller.deleteMessagePermanently(widget.message);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Failed to permanently delete message: $error');
        debugPrintStack(stackTrace: stack);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingPermanentRemoval = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر حذف الرسالة نهائيًا'),
        ),
      );
    }
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
    final onBubble = widget.isMine
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

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground({
    required this.visible,
    required this.isActive,
    required this.borderRadius,
    required this.alignment,
  });

  final bool visible;
  final bool isActive;
  final BorderRadius borderRadius;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    final iconColor = theme.colorScheme.onError;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isActive ? color : color.withOpacity(0.85),
                borderRadius: borderRadius,
              ),
              child: Align(
                alignment: alignment,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(
                    Icons.delete_forever_rounded,
                    color: iconColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermanentDeleteConfirmationSheet extends StatelessWidget {
  const _PermanentDeleteConfirmationSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyColor = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete this message permanently?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone and will remove the message for everyone.',
              style: theme.textTheme.bodyMedium?.copyWith(color: bodyColor),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showMessageActions(
  BuildContext context,
  ChatMessage message,
  bool isMine,
) async {
  final controller = context.read<ChatThreadController>();
  final List<_MessageActionItem> actions = <_MessageActionItem>[
    _MessageActionItem('reply', 'رد', Icons.reply_rounded),
    _MessageActionItem(
      'forward',
      'إعادة توجيه',
      Icons.forward_to_inbox_rounded,
    ),
    if (message.text != null && message.text!.isNotEmpty)
      _MessageActionItem('copy', 'نسخ', Icons.copy_rounded),
    if (message.text != null && message.text!.isNotEmpty)
      _MessageActionItem('translate', 'ترجمة', Icons.translate_rounded),
    if (isMine)
      _MessageActionItem(
        'delete-all',
        'حذف للجميع',
        Icons.delete_forever_rounded,
      ),
    _MessageActionItem(
      'delete-me',
      'حذف عندي فقط',
      Icons.delete_outline_rounded,
    ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم نسخ الرسالة')));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('تعذر تنفيذ العملية: $err')));
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
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
          Text(
            'إرسال إلى محادثة أخرى',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                    title: Text(
                      other,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('تمت إعادة التوجيه')));
}

class _TypingBanner extends StatelessWidget {
  const _TypingBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatThreadController>(
      builder: (context, controller, _) {
        if (!controller.isOtherTyping) {
          debugPrint(
            'TypingBanner: hidden for thread ${controller.threadId} (no active typing)',
          );
          return const SizedBox.shrink();
        }
        final otherUid = controller.otherUid;
        if (otherUid == null || otherUid.isEmpty) {
          debugPrint(
            'TypingBanner: falling back to classic indicator for thread ${controller.threadId} (missing otherUid)',
          );
          return _TypingBannerText(text: _fallbackTypingLabel(context));
        }
        final previewService = context.read<TypingPreviewService>();
        return StreamBuilder<TypingPreviewState>(
          key: ValueKey<String>('preview-${controller.threadId}-$otherUid'),
          stream: previewService.watchTypingPreview(
            conversationId: controller.threadId,
            otherUserId: otherUid,
          ),
          builder: (context, snapshot) {
            final state = snapshot.data;
            final previewText = state?.viewableText;
            final hasPreview = previewText != null && previewText.isNotEmpty;
            final label = hasPreview
                ? _formatPreviewLabel(context, previewText)
                : _fallbackTypingLabel(context);
            if (hasPreview) {
              debugPrint(
                'TypingBanner: showing preview for thread ${controller.threadId} (length: ${previewText!.length})',
              );
            } else {
              debugPrint(
                'TypingBanner: falling back to classic indicator for thread ${controller.threadId}',
              );
            }
            return _TypingBannerText(text: label);
          },
        );
      },
    );
  }

  static String _fallbackTypingLabel(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context)?.languageCode;
    final isArabic =
        locale == 'ar' || Directionality.of(context) == TextDirection.rtl;
    return isArabic ? 'يكتب الآن…' : 'Typing…';
  }

  static String _formatPreviewLabel(BuildContext context, String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final truncated = cleaned.characters.take(40).toString();
    final locale = Localizations.maybeLocaleOf(context)?.languageCode;
    final isArabic =
        locale == 'ar' || Directionality.of(context) == TextDirection.rtl;
    final prefix = isArabic ? 'يكتب الآن: ' : 'Typing: ';
    return '$prefix$truncated';
  }
}

class _TypingBannerText extends StatelessWidget {
  const _TypingBannerText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Container(
        key: ValueKey<String>(text),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: theme.colorScheme.surfaceVariant,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: style,
        ),
      ),
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
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
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
    final typingPreviewService = context.read<TypingPreviewService>();
    unawaited(
      typingPreviewService.sendTypingPreview(
        conversationId: controller.threadId,
        text: '',
      ),
    );
    unawaited(controller.updateTyping(false));
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (_showSend != hasText) {
      setState(() => _showSend = hasText);
    }
    final controller = context.read<ChatThreadController>();
    final typingPreviewService = context.read<TypingPreviewService>();
    unawaited(
      typingPreviewService.sendTypingPreview(
        conversationId: controller.threadId,
        text: _controller.text,
      ),
    );
    unawaited(controller.updateTyping(hasText));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatThreadController>();
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (controller.isUploading) const LinearProgressIndicator(minHeight: 2),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر إرسال الرسالة: $err')),
                      );
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر إرسال التسجيل: $err')),
                      );
                    }
                  },
                  onLongPressCancel: () =>
                      unawaited(controller.cancelRecording()),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذر اختيار ملف: $err')),
                  );
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تعذر فتح الكاميرا: $err')),
                  );
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
              Text('لوحة الإيموجي ستتوفر قريباً!'),
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
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
        ),
      );
    }
    final heroTag = 'chat-media-$messageId';
    final border = BorderRadius.circular(18);
    final previewUrl = (thumbnailUrl?.isNotEmpty ?? false)
        ? thumbnailUrl!
        : url!;
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
                  placeholder: (context, _) => Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                  ),
                  errorWidget: (context, _, __) => Container(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 36,
                    ),
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
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 36,
                    color: Colors.white,
                  ),
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
                          child: CircularProgressIndicator(
                            color: Colors.white70,
                          ),
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
    _initialization = _controller
        .initialize()
        .then((_) {
          if (!mounted) {
            return;
          }
          setState(() {});
          _controller
            ..setLooping(true)
            ..play();
        })
        .catchError((Object error, StackTrace stack) {
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
        Icon(
          Icons.insert_drive_file_rounded,
          color: isMine ? Colors.white : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$name $sizeText',
            style: TextStyle(
              color: isMine
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
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
  const _AudioMessageBubble({
    required this.url,
    required this.isMine,
    this.duration,
  });

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
              icon: Icon(
                playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
              ),
              color: Colors.white,
              onPressed: _toggle,
            ),
            Text(
              _formatDuration(_position),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDuration(_duration),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
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
