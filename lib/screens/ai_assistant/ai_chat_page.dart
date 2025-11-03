import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../modules/ai_assistant/ai_assistant_controller.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, required this.userId});

  final String userId;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final AiAssistantController _controller;
  late final TextEditingController _inputController;
  final ScrollController _scrollController = ScrollController();
  String? _lastErrorMessage;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AiAssistantController();
    _controller.addListener(_handleControllerChanged);
    _inputController = TextEditingController();
    unawaited(_controller.initialize(userId: widget.userId));
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    final int count = _controller.messages.length;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    final String? error = _controller.errorMessage;
    if (error != null && error.isNotEmpty && error != _lastErrorMessage) {
      _lastErrorMessage = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      });
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed('/settings');
    if (!mounted) return;
    await _controller.refreshBotMode();
  }

  void _handleSend() {
    final String text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.sendMessage(text);
    _inputController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AiAssistantController>.value(
      value: _controller,
      child: Consumer<AiAssistantController>(
        builder: (BuildContext context, AiAssistantController controller, _) {
          final List<AiChatMessage> messages = controller.messages;
          final int limit = AiAssistantController.dailyLimitForPlan(controller.plan);
          final int usedToday = _countMessagesToday(messages);

          return Scaffold(
            appBar: AppBar(
              title: Text('المساعد الذكي — ${AiAssistantController.readableBotLabel(controller.botMode)}'),
              actions: [
                IconButton(
                  tooltip: 'إعدادات المساعد',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_suggest_rounded),
                ),
              ],
            ),
            body: Column(
              children: [
                _AiUsageHeader(
                  plan: controller.plan,
                  limit: limit,
                  used: usedToday,
                  botMode: controller.botMode,
                ),
                const Divider(height: 1),
                Expanded(
                  child: controller.loading
                      ? const Center(
                          child: SpinKitThreeBounce(color: Colors.teal, size: 36),
                        )
                      : _buildMessagesList(messages, controller.isSending),
                ),
                const Divider(height: 1),
                _buildComposer(controller),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessagesList(List<AiChatMessage> messages, bool isSending) {
    if (messages.isEmpty && !isSending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.smart_toy_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'ابدأ المحادثة مع المساعد الذكي.\nاكتب سؤالك وسيتم حفظ المحادثة تلقائياً.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
          itemCount: messages.length,
          itemBuilder: (BuildContext context, int index) {
            final AiChatMessage message = messages[index];
            final bool isUser = message.isUser;
            return Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  color: isUser
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.9)
                      : Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16).copyWith(
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isUser)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: Icon(Icons.smart_toy_rounded,
                                size: 14, color: Theme.of(context).colorScheme.primary),
                          ),
                        Text(
                          DateFormat('HH:mm').format(message.createdAt),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: isUser
                                    ? Theme.of(context).colorScheme.onPrimary.withOpacity(0.8)
                                    : Theme.of(context).hintColor,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        if (isSending)
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SpinKitThreeBounce(color: Colors.teal, size: 18),
                  SizedBox(width: 8),
                  Text('المساعد يكتب...'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildComposer(AiAssistantController controller) {
    final bool disabled = controller.isSending || controller.limitReached;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Row(
          children: [
            IconButton(
              tooltip: 'رسالة صوتية (قريباً)',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('دعم الرسائل الصوتية قادم قريباً.')),
                );
              },
              icon: const Icon(Icons.mic_none_rounded),
            ),
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
                enabled: !disabled,
                decoration: InputDecoration(
                  hintText: controller.limitReached
                      ? 'تم بلوغ الحد اليومي للخطة الحالية'
                      : 'اكتب رسالة للمساعد...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  filled: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: disabled ? null : _handleSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
  }

  int _countMessagesToday(List<AiChatMessage> messages) {
    final DateTime today = DateTime.now();
    return messages
        .where((AiChatMessage m) =>
            m.isUser &&
            m.createdAt.year == today.year &&
            m.createdAt.month == today.month &&
            m.createdAt.day == today.day)
        .length;
  }
}

class _AiUsageHeader extends StatelessWidget {
  const _AiUsageHeader({
    required this.plan,
    required this.limit,
    required this.used,
    required this.botMode,
  });

  final String plan;
  final int limit;
  final int used;
  final String botMode;

  @override
  Widget build(BuildContext context) {
    final String botLabel = AiAssistantController.readableBotLabel(botMode);
    final String description =
        kBotModeDescriptions[botMode] ?? kBotModeDescriptions['general']!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'خطة المستخدم: ${AiAssistantController.readablePlanLabel(plan)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('الرسائل المتاحة اليوم: $used / $limit'),
          const SizedBox(height: 4),
          Text('الوضع الحالي: $botLabel'),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}
