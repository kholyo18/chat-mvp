import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/services/ai_insight_service.dart';

class OpenAiDiagnosticsPage extends StatefulWidget {
  const OpenAiDiagnosticsPage({super.key});

  @override
  State<OpenAiDiagnosticsPage> createState() => _OpenAiDiagnosticsPageState();
}

class _OpenAiDiagnosticsPageState extends State<OpenAiDiagnosticsPage> {
  final AiInsightService _service = AiInsightService();
  OpenAiDiagResult? _result;
  bool _testing = false;

  Future<void> _runTest() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _result = null;
    });
    final result = await _service.ping();
    if (!mounted) return;
    setState(() {
      _result = result;
      _testing = false;
    });
  }

  Future<void> _copyDetails() async {
    final result = _result;
    if (result == null) return;
    final payload = jsonEncode(result.toJson());
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ التفاصيل إلى الحافظة')),
    );
  }

  Widget _buildResultCard(ThemeData theme) {
    final result = _result;
    if (result == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('اضغط على الزر أدناه لاختبار الاتصال.'),
              ),
            ],
          ),
        ),
      );
    }

    final bool success = result.ok;
    final Color iconColor = success ? Colors.green : theme.colorScheme.error;
    final IconData icon = success ? Icons.check_circle : Icons.error_outline;
    final String title = success
        ? 'متصل بنجاح'
        : 'تعذر الاتصال بخدمة OpenAI';
    final String subtitle = success
        ? 'عدد النماذج: ${result.modelsCount ?? 0}'
        : (result.message ?? 'حدث خطأ غير معروف');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(subtitle, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (!success) ...[
              const SizedBox(height: 16),
              const Text('جرّب الخطوات التالية:'),
              const SizedBox(height: 8),
              const _HintList(),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _testing ? null : _runTest,
                  child: const Text('إعادة المحاولة'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _copyDetails,
                  child: const Text('نسخ التفاصيل'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار اتصال OpenAI')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'يقوم هذا الاختبار بمحاولة الاتصال بخوادم OpenAI باستخدام الإعدادات الحالية، '
              'ويعرض حالة المفتاح وحالة الشبكة في الوقت الفعلي.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _testing ? null : _runTest,
                child: _testing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('اختبار الاتصال الآن'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _buildResultCard(theme),
                  if (_result == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: _HintList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintList extends StatelessWidget {
  const _HintList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _HintBullet('تأكد من وجود OPENAI_API_KEY في .env'),
        _HintBullet('أعد تشغيل التطبيق بالكامل'),
        _HintBullet('جرّب VPN أو شبكة أخرى'),
        _HintBullet('تأكد من وجود رصيد في OpenAI Usage'),
      ],
    );
  }
}

class _HintBullet extends StatelessWidget {
  const _HintBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
