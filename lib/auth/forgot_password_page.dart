import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'البريد الإلكتروني مطلوب / Email required';
    }
    final hasAt = email.contains('@');
    final hasDot = email.contains('.');
    if (!hasAt || !hasDot) {
      return 'الرجاء إدخال بريد إلكتروني صالح / Please enter a valid email.';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (_sending) return;
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      await AuthService.sendPasswordResetEmail(_emailCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إرسال رابط إعادة التعيين إلى بريدك ✅\nPassword reset link has been sent to your email.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final friendly = raw.startsWith('Exception: ')
          ? raw.replaceFirst('Exception: ', '')
          : raw;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$friendly\nPlease try again shortly.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعادة تعيين كلمة المرور / Reset Password'),
          leading: const BackButton(),
        ),
        body: Container(
          width: double.infinity,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 36,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(.12),
                                  child: Icon(
                                    Icons.lock_reset_rounded,
                                    size: 36,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'نسيت كلمة المرور؟ لا تقلق!\nForgot your password? We\'ve got you.',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailCtrl,
                            textDirection: ui.TextDirection.rtl,
                            textAlign: TextAlign.end,
                            keyboardType: TextInputType.emailAddress,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            decoration: InputDecoration(
                              labelText: 'البريد الإلكتروني / Email',
                              hintText: 'example@mail.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            validator: _validateEmail,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _sending ? null : _handleSubmit,
                              icon: _sending
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.6,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Theme.of(context)
                                              .colorScheme
                                              .onPrimary,
                                        ),
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(
                                _sending
                                    ? 'جاري الإرسال... / Sending...'
                                    : 'إرسال رابط إعادة التعيين / Send reset link',
                              ),
                            ),
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
      ),
    );
  }
}
