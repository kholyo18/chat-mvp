import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _submitting = false;
  bool _accountCreated = false;
  String? _errorMessage;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'الاسم مطلوب';
    }
    if (value.trim().length < 3) {
      return 'الاسم يجب أن يتكون من 3 أحرف على الأقل';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'البريد الإلكتروني مطلوب';
    }
    final email = value.trim();
    final emailValid = email.contains('@') && email.contains('.');
    if (!emailValid) {
      return 'الرجاء إدخال بريد إلكتروني صالح';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'كلمة المرور مطلوبة';
    }
    final hasLetter = value.contains(RegExp(r'[A-Za-z]'));
    final hasDigit = value.contains(RegExp(r'[0-9]'));
    if (value.length < 8 || !hasLetter || !hasDigit) {
      return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل وتشمل حرفًا ورقمًا';
    }
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value == null || value.isEmpty) {
      return 'تأكيد كلمة المرور مطلوب';
    }
    if (value != _passwordCtrl.text) {
      return 'كلمتا المرور غير متطابقتين';
    }
    return null;
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'هذا البريد مستخدم مسبقًا. جرّب تسجيل الدخول بدلاً من ذلك.';
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة جدًا. اختر كلمة مرور أقوى.';
      case 'operation-not-allowed':
        return 'تم تعطيل التسجيل بالبريد الإلكتروني مؤقتًا.';
      default:
        return 'حدث خطأ غير متوقع. حاول لاحقًا.';
    }
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      await AuthService.signUpWithEmail(
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      setState(() => _accountCreated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء الحساب! تحقق من بريدك لتفعيل الحساب.')),
      );
    } on FirebaseAuthException catch (e) {
      final friendly = _mapAuthError(e.code);
      if (!mounted) return;
      setState(() => _errorMessage = friendly);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } catch (e) {
      if (!mounted) return;
      const fallback = 'تعذر إنشاء الحساب. حاول لاحقًا.';
      setState(() => _errorMessage = fallback);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(fallback)));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _resendVerification() async {
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
    }
  }

  Widget _buildSuccessCard() {
    final email = _emailCtrl.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_rounded,
            size: 64, color: Color(0xFF26A69A)),
        const SizedBox(height: 16),
        Text(
          'تحقق من بريدك الإلكتروني',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'أرسلنا رابط التفعيل إلى $email. افتح بريدك ثم اضغط على "تحديث الحالة" بعد التفعيل.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed('/auth/verify-email'),
            child: const Text('متابعة إلى التحقق'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _resendVerification,
          child: const Text('إعادة إرسال بريد التفعيل'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Padding(
                      key: ValueKey(_accountCreated),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      child: _accountCreated
                          ? _buildSuccessCard()
                          : _buildForm(),
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

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        CircleAvatar(
          radius: 32,
          backgroundColor:
              Theme.of(context).colorScheme.primary.withOpacity(0.12),
          child: Icon(Icons.person_add_alt_1_rounded,
              size: 36, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          'إنشاء حساب جديد',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'انضم إلى Chat Ultra بالبريد الإلكتروني وكلمة المرور.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 24),
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _fullNameCtrl,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: _inputDecoration(
                  label: 'الاسم الكامل',
                  icon: Icons.badge_rounded,
                ),
                validator: _validateFullName,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  label: 'البريد الإلكتروني',
                  icon: Icons.email_rounded,
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passwordCtrl,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                obscureText: true,
                decoration: _inputDecoration(
                  label: 'كلمة المرور',
                  icon: Icons.lock_rounded,
                  helper: '8 أحرف على الأقل وتحتوي على حرف ورقم',
                ),
                validator: _validatePassword,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmCtrl,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                obscureText: true,
                decoration: _inputDecoration(
                  label: 'تأكيد كلمة المرور',
                  icon: Icons.verified_user_rounded,
                ),
                validator: _validateConfirm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _submitting ? null : _handleSubmit,
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  )
                : const Text('إنشاء الحساب'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).maybePop(),
          child: const Text('لديك حساب بالفعل؟ سجل الدخول'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
