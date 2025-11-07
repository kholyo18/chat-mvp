import 'dart:async';

import 'package:agora_rtc_engine/rtc_local_view.dart' as rtc_local_view;
import 'package:agora_rtc_engine/rtc_remote_view.dart' as rtc_remote_view;
import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:flutter/material.dart';

import 'agora_call_client.dart';
import 'dm_call_models.dart';

typedef DmCallTerminateCallback = Future<void> Function(
  DmCallSession session, {
  bool remoteEnded,
});

class DmCallPage extends StatefulWidget {
  const DmCallPage({
    super.key,
    required this.session,
    this.onAnswerIncomingCall,
    this.onDeclineIncomingCall,
    required this.onEnsureActiveCall,
    required this.onTerminateCall,
  });

  final DmCallSession session;
  final Future<void> Function(DmCallSession session)? onAnswerIncomingCall;
  final Future<void> Function(DmCallSession session)? onDeclineIncomingCall;
  final Future<void> Function(DmCallSession session) onEnsureActiveCall;
  final DmCallTerminateCallback onTerminateCall;

  @override
  State<DmCallPage> createState() => _DmCallPageState();
}

class _DmCallPageState extends State<DmCallPage> {
  late final cf.DocumentReference<Map<String, dynamic>> _callRef;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  bool _endedLocally = false;
  final AgoraCallClient _callClient = AgoraCallClient.instance;
  DmCallSession? _latestSession;
  bool _joiningAgora = false;

  @override
  void initState() {
    super.initState();
    _callRef = cf.FirebaseFirestore.instance.collection('calls').doc(widget.session.callId);
    _callSub = _callRef.snapshots().listen(_handleSnapshot, onError: _logError);
  }

  @override
  void dispose() {
    _callSub?.cancel();
    if (!_endedLocally) {
      final session = _latestSession ?? widget.session;
      unawaited(_terminateCall(session, silent: true));
    }
    super.dispose();
  }

  void _handleSnapshot(cf.DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      return;
    }
    if (data['status'] == 'ended' && !_endedLocally) {
      final session = _latestSession ?? widget.session;
      unawaited(_terminateCall(session, remoteEnded: true, silent: true));
      if (mounted) {
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          Navigator.of(context).maybePop();
        });
      }
    }
  }

  void _logError(Object error, StackTrace stack) {
    debugPrint('DmCallPage error: $error');
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack));
  }

  Future<void> _terminateCall(
    DmCallSession session, {
    bool remoteEnded = false,
    bool silent = false,
  }) async {
    if (!remoteEnded && _endedLocally) {
      return;
    }
    _endedLocally = true;
    try {
      await widget.onTerminateCall(session, remoteEnded: remoteEnded);
    } catch (err, stack) {
      if (!silent) {
        _logError(err, stack);
        _showOperationFailedSnackBar(
          remoteEnded
              ? 'تعذر إنهاء المكالمة بشكل صحيح.'
              : 'تعذر إنهاء المكالمة، يرجى المحاولة مرة أخرى.',
        );
      }
    }
  }

  void _showOperationFailedSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showAgoraErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _ensureAgoraSession(DmCallSession session) {
    final status = session.status.toLowerCase();
    if (status != 'active' && status != 'in-progress') {
      return;
    }
    if (_joiningAgora) {
      return;
    }
    _joiningAgora = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.onEnsureActiveCall(session);
      } on AgoraPermissionException {
        if (mounted) {
          _showAgoraErrorSnackBar('يرجى منح صلاحيات الميكروفون/الكاميرا للمكالمة.');
        }
      } catch (err, stack) {
        _logError(err, stack);
        if (mounted) {
          _showAgoraErrorSnackBar('تعذر الاتصال بالمكالمة. حاول مرة أخرى.');
        }
      } finally {
        _joiningAgora = false;
      }
    });
  }

  Future<void> _handleEnd(DmCallSession session) async {
    await _terminateCall(session);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _handleAccept(DmCallSession session) async {
    final callback = widget.onAnswerIncomingCall;
    if (callback == null) {
      return;
    }
    try {
      await callback(session);
    } catch (err, stack) {
      _logError(err, stack);
      _showOperationFailedSnackBar('تعذر قبول المكالمة، حاول مرة أخرى.');
    }
  }

  Future<void> _handleDecline(DmCallSession session) async {
    final callback = widget.onDeclineIncomingCall;
    if (callback == null) {
      return;
    }
    try {
      _endedLocally = true;
      await callback(session);
    } catch (err, stack) {
      _logError(err, stack);
      _showOperationFailedSnackBar('تعذر رفض المكالمة، حاول مرة أخرى.');
    }
  }

  Future<void> _handleToggleMute() async {
    try {
      await _callClient.toggleMute();
    } on AgoraCallException {
      _showAgoraErrorSnackBar('انتظر بدء الاتصال قبل التحكم في الميكروفون.');
    } catch (err, stack) {
      _logError(err, stack);
      _showAgoraErrorSnackBar('تعذر تغيير حالة الميكروفون، حاول مرة أخرى.');
    }
  }

  Future<void> _handleToggleSpeaker() async {
    try {
      await _callClient.toggleSpeakerphone();
    } on AgoraCallException {
      _showAgoraErrorSnackBar('انتظر بدء الاتصال قبل استخدام مكبر الصوت.');
    } catch (err, stack) {
      _logError(err, stack);
      _showAgoraErrorSnackBar('تعذر تغيير وضع مكبر الصوت، حاول مرة أخرى.');
    }
  }

  Future<void> _handleSwitchCamera() async {
    try {
      await _callClient.switchCamera();
    } on AgoraCallException {
      _showAgoraErrorSnackBar('لا يمكن تبديل الكاميرا الآن.');
    } catch (err, stack) {
      _logError(err, stack);
      _showAgoraErrorSnackBar('تعذر تبديل الكاميرا، حاول مرة أخرى.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<cf.DocumentSnapshot<Map<String, dynamic>>>(
          stream: _callRef.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorView(onClose: () => Navigator.of(context).maybePop());
            }
            if (!snapshot.hasData) {
              return const _CallLoading();
            }
            final data = snapshot.data!.data();
            if (data == null) {
              return const _CallLoading();
            }
            final status = (data['status'] as String?) ?? 'ringing';
            final participantsRaw = data['participants'] as Map<String, dynamic>?;
            final participants = _parseParticipants(participantsRaw);
            if (participants.isEmpty) {
              return const _CallLoading();
            }
            final session = widget.session.copyWith(
              participants: participants,
              status: status,
            );
            _latestSession = session;
            _ensureAgoraSession(session);
            return _CallContent(
              session: session,
              callClient: _callClient,
              onEnd: () => unawaited(_handleEnd(session)),
              onAccept: widget.onAnswerIncomingCall == null
                  ? null
                  : () => unawaited(_handleAccept(session)),
              onDecline: widget.onDeclineIncomingCall == null
                  ? null
                  : () => unawaited(_handleDecline(session)),
              onToggleMute: () => unawaited(_handleToggleMute()),
              onToggleSpeaker: () => unawaited(_handleToggleSpeaker()),
              onSwitchCamera: session.type == DmCallType.video
                  ? () => unawaited(_handleSwitchCamera())
                  : null,
            );
          },
        ),
      ),
    );
  }

  List<DmCallParticipant> _parseParticipants(Map<String, dynamic>? map) {
    if (map == null) {
      return widget.session.participants;
    }
    final result = <DmCallParticipant>[];
    map.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final displayName = (value['displayName'] as String?)?.trim();
        final avatarUrl = (value['avatarUrl'] as String?)?.trim();
        final role = (value['role'] as String?) ?? 'participant';
        final state = (value['state'] as String?) ?? 'ringing';
        result.add(
          DmCallParticipant(
            uid: key,
            displayName: displayName?.isNotEmpty == true ? displayName! : key,
            avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
            role: role,
            state: state,
          ),
        );
      }
    });
    if (result.isEmpty) {
      return widget.session.participants;
    }
    return result;
  }
}

class _CallContent extends StatelessWidget {
  const _CallContent({
    required this.session,
    required this.callClient,
    required this.onEnd,
    this.onAccept,
    this.onDecline,
    this.onToggleMute,
    this.onToggleSpeaker,
    this.onSwitchCamera,
  });

  final DmCallSession session;
  final AgoraCallClient callClient;
  final VoidCallback onEnd;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleSpeaker;
  final VoidCallback? onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    if (session.isRingingForCurrentUser && onAccept != null && onDecline != null) {
      return _IncomingCallView(
        session: session,
        onAccept: onAccept!,
        onDecline: onDecline!,
      );
    }
    return _ActiveCallView(
      session: session,
      callClient: callClient,
      onEnd: onEnd,
      onToggleMute: onToggleMute,
      onToggleSpeaker: onToggleSpeaker,
      onSwitchCamera: onSwitchCamera,
    );
  }
}

class _ActiveCallView extends StatelessWidget {
  const _ActiveCallView({
    required this.session,
    required this.callClient,
    required this.onEnd,
    this.onToggleMute,
    this.onToggleSpeaker,
    this.onSwitchCamera,
  });

  final DmCallSession session;
  final AgoraCallClient callClient;
  final VoidCallback onEnd;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleSpeaker;
  final VoidCallback? onSwitchCamera;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remote = session.otherParticipant ??
        session.caller ??
        session.callee ??
        (session.participants.isNotEmpty ? session.participants.first : null);
    final statusLabel = _statusLabel(session.status);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              onPressed: onEnd,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'إنهاء',
            ),
          ),
          Expanded(
            child: session.type == DmCallType.video
                ? _VideoCallBody(
                    session: session,
                    callClient: callClient,
                    remote: remote,
                    statusLabel: statusLabel,
                  )
                : _AudioCallBody(
                    remote: remote,
                    statusLabel: statusLabel,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: callClient.isMuted,
                  builder: (context, muted, _) {
                    return _CallActionButton(
                      icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      label: 'كتم',
                      background: muted ? Colors.redAccent : Colors.white12,
                      onPressed: onToggleMute,
                    );
                  },
                ),
                const SizedBox(width: 24),
                _CallActionButton(
                  icon: Icons.call_end_rounded,
                  label: 'إنهاء',
                  background: Colors.redAccent,
                  onPressed: onEnd,
                ),
                const SizedBox(width: 24),
                session.type == DmCallType.video
                    ? _CallActionButton(
                        icon: Icons.cameraswitch_rounded,
                        label: 'فيديو',
                        onPressed: onSwitchCamera,
                      )
                    : ValueListenableBuilder<bool>(
                        valueListenable: callClient.isSpeakerEnabled,
                        builder: (context, speakerOn, _) {
                          return _CallActionButton(
                            icon: speakerOn
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            label: 'مكبر',
                            background:
                                speakerOn ? Colors.greenAccent : Colors.white12,
                            onPressed: onToggleSpeaker,
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
      case 'in-progress':
        return 'متصل';
      case 'ended':
        return 'انتهت المكالمة';
      default:
        return 'جارٍ الاتصال…';
    }
  }
}

class _AudioCallBody extends StatelessWidget {
  const _AudioCallBody({required this.remote, required this.statusLabel});

  final DmCallParticipant? remote;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AvatarPlaceholder(
          url: remote?.avatarUrl,
          label: remote?.displayName ?? 'مكالمة جارية',
        ),
        const SizedBox(height: 24),
        Text(
          remote?.displayName ?? 'مكالمة جارية',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          statusLabel,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _VideoCallBody extends StatelessWidget {
  const _VideoCallBody({
    required this.session,
    required this.callClient,
    required this.remote,
    required this.statusLabel,
  });

  final DmCallSession session;
  final AgoraCallClient callClient;
  final DmCallParticipant? remote;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<Set<int>>(
                  valueListenable: callClient.remoteUserIds,
                  builder: (context, remoteUsers, _) {
                    final remoteUid = remoteUsers.isNotEmpty ? remoteUsers.first : null;
                    if (remoteUid != null) {
                      return rtc_remote_view.SurfaceView(
                        channelId: session.channelId,
                        uid: remoteUid,
                      );
                    }
                    return Container(
                      color: Colors.black87,
                      alignment: Alignment.center,
                      child: Text(
                        'بانتظار انضمام الطرف الآخر…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
                PositionedDirectional(
                  top: 16,
                  end: 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 120,
                      height: 160,
                      color: Colors.black54,
                      child: rtc_local_view.SurfaceView(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          remote?.displayName ?? 'مكالمة فيديو',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          statusLabel,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _IncomingCallView extends StatelessWidget {
  const _IncomingCallView({
    required this.session,
    required this.onAccept,
    required this.onDecline,
  });

  final DmCallSession session;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caller = session.caller ?? session.otherParticipant;
    final direction = Directionality.of(context);
    final callLabel = session.type == DmCallType.video ? 'مكالمة فيديو' : 'مكالمة صوتية';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _AvatarPlaceholder(
                  url: caller?.avatarUrl,
                  label: caller?.displayName ?? 'مكالمة واردة',
                ),
                const SizedBox(height: 24),
                Text(
                  caller?.displayName ?? 'مكالمة واردة',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'يتصل بك…',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  callLabel,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              textDirection: direction,
              children: [
                _IncomingActionButton(
                  background: Colors.redAccent,
                  icon: Icons.call_end_rounded,
                  label: 'رفض',
                  onPressed: onDecline,
                ),
                _IncomingActionButton(
                  background: Colors.greenAccent,
                  icon: Icons.call_rounded,
                  label: 'قبول',
                  onPressed: onAccept,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingActionButton extends StatelessWidget {
  const _IncomingActionButton({
    required this.background,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color background;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RawMaterialButton(
          onPressed: onPressed,
          elevation: 0,
          fillColor: background,
          padding: const EdgeInsets.all(22),
          shape: const CircleBorder(),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.background,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RawMaterialButton(
          onPressed: onPressed,
          elevation: 0,
          fillColor: background ?? Colors.white12,
          padding: const EdgeInsets.all(18),
          shape: const CircleBorder(),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.url, required this.label});

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(url!),
      );
    }
    return CircleAvatar(
      radius: 48,
      backgroundColor: Colors.white12,
      child: Text(
        label.isNotEmpty ? label.characters.first : '?',
        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CallLoading extends StatelessWidget {
  const _CallLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          const Text(
            'تعذر تحميل المكالمة',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onClose,
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
