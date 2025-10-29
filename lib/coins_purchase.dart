import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const String baseUrl =
    'https://us-central1-chat-mvp-20750.cloudfunctions.net';
const String createSessionPath = '/createCheckoutSession';

final List<_CoinsPack> packs = [
  _CoinsPack(label: '100 coins', coins: 100, unitPriceEur: 1.0),
  _CoinsPack(label: '550 coins', coins: 550, unitPriceEur: 4.0),
  _CoinsPack(label: '1500 coins', coins: 1500, unitPriceEur: 9.0),
];

class _CoinsPack {
  final String label;
  final int coins;
  final double unitPriceEur;
  const _CoinsPack({required this.label, required this.coins, required this.unitPriceEur});
}

class CoinsPurchasePage extends StatefulWidget {
  const CoinsPurchasePage({super.key});
  @override
  State<CoinsPurchasePage> createState() => _CoinsPurchasePageState();
}

class _CoinsPurchasePageState extends State<CoinsPurchasePage> {
  bool _loading = false;

  Stream<int?> _coinsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream<int?>.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((d) => (d.data()?['coins'] as int?) ?? 0);
  }

  Future<void> _buyPack(_CoinsPack pack) async {
    try {
      setState(() => _loading = true);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('سجّل الدخول أولاً')),
          );
        }
        return;
      }
      final uri = Uri.parse('$baseUrl$createSessionPath');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'metadata': {'uid': uid},
          'coins': pack.coins,
          'amount_eur': pack.unitPriceEur,
          'success_url': 'https://example.com/success',
          'cancel_url': 'https://example.com/cancel',
        }),
      );
      if (res.statusCode != 200) {
        throw Exception('فشل إنشاء جلسة الدفع (${res.statusCode}) ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final checkoutUrl = data['url'] as String?;
      if (checkoutUrl == null) throw Exception('لم أستلم checkout URL من الخادم');

      final ok = await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('تعذّر فتح صفحة الدفع');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recharge Coins')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StreamBuilder<int?>(
              stream: _coinsStream(),
              builder: (context, snap) {
                final coins = snap.data ?? 0;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.monetization_on),
                    title: const Text('رصيدك الحالي'),
                    subtitle: Text('$coins coins'),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: packs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = packs[i];
                  return Card(
                    child: ListTile(
                      title: Text(p.label),
                      subtitle: Text('€${p.unitPriceEur.toStringAsFixed(2)}'),
                      trailing: ElevatedButton(
                        onPressed: _loading ? null : () => _buyPack(p),
                        child: _loading
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('اشتري'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
