import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'dm_call_models.dart';

class DmCallPage extends StatefulWidget {
  const DmCallPage({
    super.key,
    required this.session,
    this.onAnswerIncomingCall,
    this.onDeclineIncomingCall,
  });

  final DmCallSession session;
  final Future<void> Function(DmCallSession session)? onAnswerIncomingCall;
  final Future<void> Function(DmCallSession session)? onDeclineIncomingCall;

  @override
  State<DmCallPage> createState() => _DmCallPageState();
}

class _DmCallPageState extends State<DmCallPage> {
  late final cf.DocumentReference<Map<String, dynamic>> _callRef;
  StreamSubscription<cf.DocumentSnapshot<Map<String, dynamic>>>? _callSub;
  bool _endedLocally = false;

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
      unawaited(_endCall(silent: true));
    }
    super.dispose();
  }

  void _handleSnapshot(cf.DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      return;
    }
    if (data['status'] == 'ended' && !_endedLocally) {
      _endedLocally = true;
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

  Future<void> _endCall({bool silent = false}) async {
    if (_endedLocally) return;
    _endedLocally = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final payload = <String, dynamic>{
      'status': 'ended',
      'endedAt': cf.FieldValue.serverTimestamp(),
      'ringingTargets': <String>[],
    };
    if (uid != null) {
      payload['participants.$uid.state'] = 'ended';
      payload['participants.$uid.leftAt'] = cf.FieldValue.serverTimestamp();
    }
    try {
      await _callRef.update(payload);
    } catch (err, stack) {
      if (!silent) {
        _logError(err, stack);
        _showOperationFailedSnackBar();
      }
    }
  }

  void _showOperationFailedSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر تحديث حالة المكالمة، يرجى المحاولة مرة أخرى.'),
      ),
    );
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
            return _CallContent(
              session: session,
              onEnd: () async {
                await _endCall();
                if (!mounted) return;
                Navigator.of(context).maybePop();
              },
              onAccept: widget.onAnswerIncomingCall == null
                  ? null
                  : () => widget.onAnswerIncomingCall!(session),
              onDecline: widget.onDeclineIncomingCall == null
                  ? null
                  : () async {
                      _endedLocally = true;
                      await widget.onDeclineIncomingCall!(session);
                    },
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
    required this.onEnd,
    this.onAccept,
    this.onDecline,
  });

  final DmCallSession session;
  final Future<void> Function() onEnd;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onDecline;

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
      onEnd: onEnd,
    );
  }
}

class _ActiveCallView extends StatelessWidget {
  const _ActiveCallView({required this.session, required this.onEnd});

  final DmCallSession session;
  final Future<void> Function() onEnd;

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
              onPressed: () => unawaited(onEnd()),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'إنهاء',
            ),
          ),
          Expanded(
            child: Column(
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CallActionButton(
                  icon: Icons.mic_off_rounded,
                  label: 'كتم',
                  onPressed: () {},
                ),
                const SizedBox(width: 24),
                _CallActionButton(
                  icon: Icons.call_end_rounded,
                  label: 'إنهاء',
                  background: Colors.redAccent,
                  onPressed: () => unawaited(onEnd()),
                ),
                const SizedBox(width: 24),
                _CallActionButton(
                  icon: session.type == DmCallType.video
                      ? Icons.videocam_off_rounded
                      : Icons.volume_up_rounded,
                  label: session.type == DmCallType.video ? 'فيديو' : 'مكبر',
                  onPressed: () {},
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

class _IncomingCallView extends StatelessWidget {
  const _IncomingCallView({
    required this.session,
    required this.onAccept,
    required this.onDecline,
  });

  final DmCallSession session;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

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
                  onPressed: () => unawaited(onDecline()),
                ),
                _IncomingActionButton(
                  background: Colors.greenAccent,
                  icon: Icons.call_rounded,
                  label: 'قبول',
                  onPressed: () => unawaited(onAccept()),
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
