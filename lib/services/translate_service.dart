// CODEX-BEGIN:TRANSLATE_SERVICE
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TranslateService {
  const TranslateService({http.Client? client}) : _client = client;

  final http.Client? _client;

  Future<String?> translate(String text, String targetLang) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.parse(
      'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$targetLang&dt=t&q=${Uri.encodeComponent(trimmed)}',
    );
    try {
      final client = _client ?? http.Client();
      final response = await client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        debugPrint('TranslateService.translate unexpected status ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is List && decoded.isNotEmpty) {
        final firstRow = decoded.first;
        if (firstRow is List && firstRow.isNotEmpty) {
          final firstCell = firstRow.first;
          if (firstCell is List && firstCell.isNotEmpty) {
            final value = firstCell.first;
            if (value is String) {
              return value;
            }
          }
        }
      }
    } on TimeoutException catch (err, stack) {
      debugPrint('TranslateService.translate timeout: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    } catch (err, stack) {
      debugPrint('TranslateService.translate error: $err');
      FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
    }
    return null;
  }
}
// CODEX-END:TRANSLATE_SERVICE
