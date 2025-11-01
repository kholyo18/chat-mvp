import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String? email;
  const EmailVerificationScreen({super.key, this.email});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  bool _checking = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      _refreshStatus(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openMailApp() async {
    final email = widget.email ?? AuthService.currentUser?.email ?? '';
    final uri = Uri(scheme: 'mailto', path: email.isEmpty ? '' : email);
    final canOpen = await canLaunchUrl(uri);
    if (!canOpen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح تطبيق البريد. افتح بريدك يدويًا.')),
      );
      return;
    }
    await launchUrl(uri);
  }

  Future<void> _resendEmail() async {
    if (_resending) return;
    setState(() => _resending = true);
    try {
      await AuthService.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال بريد التفعيل مجددًا.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال البريد. حاول لاحقًا.')),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _refreshStatus({bool silent = false}) async {
    final user = AuthService.currentUser;
    if (user == null) return;
    if (!silent) {
      setState(() => _checking = true);
    }
    try {
      await user.reload();
      final refreshed = AuthService.currentUser;
      if (refreshed != null && refreshed.emailVerified) {
        _timer?.cancel();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفعيل بريدك بنجاح!')),
        );
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return;
      }
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم التفعيل بعد. تحقق من بريدك.')),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث الحالة. حاول من جديد.')),
        );
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email = widget.email ?? AuthService.currentUser?.email ?? '';
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF0f172a), Color(0xFF1e293b)]
                  : const [Color(0xFFe6f7f4), Color(0xFFffffff)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.12),
                          child: Icon(Icons.mark_email_unread_rounded,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'تحقق من بريدك',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          email.isEmpty
                              ? 'أرسلنا رابط تفعيل إلى بريدك الإلكتروني. افتح بريدك واضغط على الرابط لإكمال التسجيل.'
                              : 'أرسلنا رابط تفعيل إلى $email. يرجى التحقق من بريدك والنقر على الرابط لإكمال التسجيل.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _openMailApp,
                            icon: const Icon(Icons.mail_rounded),
                            label: const Text('فتح تطبيق البريد'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _resending ? null : _resendEmail,
                            icon: _resending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.4),
                                  )
                                : const Icon(Icons.refresh_rounded),
                            label: Text(_resending
                                ? 'جاري الإرسال...'
                                : 'إعادة إرسال البريد'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: TextButton.icon(
                            onPressed: _checking ? null : () => _refreshStatus(),
                            icon: _checking
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.4),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(_checking ? 'جارٍ التحقق...' : 'تحديث الحالة'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'سنقوم بالتحديث التلقائي كل بضع ثوانٍ.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
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
