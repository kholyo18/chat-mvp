import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../navigation/app_navigator.dart';
import '../../services/auth_service.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loadingGoogle = false;
  bool _loadingEmail = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'البريد الإلكتروني مطلوب';
    }
    final email = value.trim();
    final valid = email.contains('@') && email.contains('.');
    if (!valid) {
      return 'الرجاء إدخال بريد إلكتروني صالح';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'كلمة المرور مطلوبة';
    }
    if (value.length < 8) {
      return 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
    }
    return null;
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'صيغة البريد الإلكتروني غير صحيحة.';
      case 'user-disabled':
        return 'تم تعطيل هذا الحساب.';
      case 'user-not-found':
        return 'لا يوجد حساب بهذا البريد. أنشئ حسابًا جديدًا.';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة. حاول مرة أخرى.';
      case 'too-many-requests':
        return 'تم حظر المحاولات مؤقتًا بسبب العديد من المحاولات الفاشلة.';
      default:
        return 'تعذر تسجيل الدخول. حاول لاحقًا.';
    }
  }

  Future<void> _handleEmailSignIn() async {
    if (_loadingEmail) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() {
      _loadingEmail = true;
      _errorMessage = null;
    });

    try {
      final credential = await AuthService.signInWithEmail(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );
      final user = credential.user;
      if (!context.mounted) return;
      if (user != null && !user.emailVerified) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final navigator = navigatorKey.currentState;
          if (navigator != null && navigator.mounted) {
            navigator.pushReplacementNamed('/auth/verify-email');
          }
        });
      } else {
        final navigator = navigatorKey.currentState;
        if (navigator != null && navigator.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final nav = navigatorKey.currentState;
            if (nav != null && nav.mounted && nav.canPop()) {
              nav.pop();
            }
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      final friendly = _mapAuthError(e.code);
      if (!context.mounted) return;
      setState(() => _errorMessage = friendly);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendly)));
    } catch (e, st) {
      if (kDebugMode) {
        print('Email sign-in error: $e\n$st');
      }
      if (!context.mounted) return;
      const fallback = 'حدث خطأ غير متوقع. حاول لاحقًا.';
      setState(() => _errorMessage = fallback);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(fallback)));
    } finally {
      if (context.mounted) {
        setState(() => _loadingEmail = false);
      }
    }
  }

  Future<void> _handleGoogle() async {
    if (_loadingGoogle) return;
    setState(() => _loadingGoogle = true);
    try {
      final userCredential = await AuthService.signInWithGoogle();
      final user = userCredential.user;
      if (user != null) {
        try {
          final navigator = await waitForRootNavigator();
          if (navigator.mounted && navigator.canPop()) {
            navigator.popUntil((route) => route.isFirst);
          }
        } on Object catch (navError, navStack) {
          if (kDebugMode) {
            print('Navigator not ready after Google Sign-In: $navError');
          }
          FlutterError.reportError(
            FlutterErrorDetails(exception: navError, stack: navStack),
          );
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('Google Sign-In error: $e\n$st');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل تسجيل الدخول: $e')));
    } finally {
      if (context.mounted) setState(() => _loadingGoogle = false);
    }
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
              padding: const EdgeInsets.all(24.0),
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
                          radius: 36,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(.12),
                          child: Icon(Icons.chat_bubble_rounded,
                              size: 36,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'أهلاً بعودتك 👋',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'سجّل دخولك للمتابعة إلى Chat Ultra.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.redAccent),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                        color: Colors.redAccent),
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
                                controller: _emailCtrl,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
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
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                obscureText: _obscurePassword,
                                decoration: _inputDecoration(
                                  label: 'كلمة المرور',
                                  icon: Icons.lock_rounded,
                                  suffix: IconButton(
                                    icon: Icon(_obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                ),
                                validator: _validatePassword,
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.of(context)
                                        .pushNamed('/forgot-password');
                                  },
                                  child: const Text(
                                    'نسيت كلمة السر؟ / Forgot password?'
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed:
                                _loadingEmail ? null : _handleEmailSignIn,
                            child: _loadingEmail
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.6,
                                    ),
                                  )
                                : const Text('تسجيل الدخول'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: const [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0),
                              child: Text('أو'),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            onPressed: _loadingGoogle ? null : _handleGoogle,
                            icon: _loadingGoogle
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.6,
                                    ),
                                  )
                                : const Icon(Icons.login_rounded),
                            label: Text(
                              _loadingGoogle
                                  ? 'جاري تسجيل الدخول...'
                                  : 'تسجيل الدخول عبر Google',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'بتسجيل الدخول، أنت توافق على الشروط وسياسة الخصوصية.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context)
                                  .pushNamed('/auth/register');
                            },
                            child: const Text('إنشاء حساب جديد'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        StreamBuilder<User?>(
                          stream: AuthService.authStateChanges,
                          builder: (context, snap) {
                            if (snap.data != null) {
                              return Text(
                                'تم تسجيل الدخول باسم ${snap.data!.email ?? snap.data!.displayName ?? ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              );
                            }
                            return const SizedBox.shrink();
                          },
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
