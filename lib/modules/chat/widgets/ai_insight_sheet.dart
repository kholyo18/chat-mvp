import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_insight.dart';

typedef AiInsightSheetAction = void Function(BuildContext context);

class AiInsightSheet extends StatelessWidget {
  const AiInsightSheet({
    super.key,
    required this.insight,
    this.isLoading = false,
    this.onTranslate,
    this.onExplainMore,
    this.onCopy,
    this.onRetry,
  });

  const AiInsightSheet.loading({super.key})
      : insight = const AiInsight(title: 'جارٍ التحليل', bullets: []),
        isLoading = true,
        onTranslate = null,
        onExplainMore = null,
        onCopy = null,
        onRetry = null;

  final AiInsight insight;
  final bool isLoading;
  final AiInsightSheetAction? onTranslate;
  final AiInsightSheetAction? onExplainMore;
  final AiInsightSheetAction? onCopy;
  final AiInsightSheetAction? onRetry;

  static Future<void> replaceWith(
    BuildContext context,
    AiInsight insight, {
    AiInsightSheetAction? onTranslate,
    AiInsightSheetAction? onExplainMore,
    AiInsightSheetAction? onCopy,
    AiInsightSheetAction? onRetry,
  }) async {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) {
      return;
    }
    navigator.pop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // ignore: use_build_context_synchronously
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AiInsightSheet(
        insight: insight,
        onTranslate: onTranslate,
        onExplainMore: onExplainMore,
        onCopy: onCopy,
        onRetry: onRetry,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.lightbulb_outline,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                insight.title,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isLoading) ...[
          _skeletonLine(theme),
          const SizedBox(height: 8),
          _skeletonLine(theme, widthFactor: 0.7),
          const SizedBox(height: 8),
          _skeletonLine(theme, widthFactor: 0.5),
        ] else ...[
          if (insight.answer != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                insight.answer!,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (insight.bullets.isNotEmpty)
            ...insight.bullets.map(
              (bullet) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(
                      child: Text(
                        bullet,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (insight.imageCaption != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                insight.imageCaption!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
          if (insight.translation != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                insight.translation!,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (insight.facts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: insight.facts
                    .map(
                      (fact) => Chip(
                        label: Text(fact),
                        backgroundColor: theme.colorScheme.surfaceVariant,
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (!isLoading)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onTranslate != null)
                OutlinedButton.icon(
                  onPressed: () => onTranslate?.call(context),
                  icon: const Icon(Icons.translate_rounded, size: 18),
                  label: const Text('Translate'),
                ),
              if (onExplainMore != null)
                OutlinedButton.icon(
                  onPressed: () => onExplainMore?.call(context),
                  icon: const Icon(Icons.light_mode_outlined, size: 18),
                  label: const Text('Explain more'),
                ),
              if (onCopy != null)
                OutlinedButton.icon(
                  onPressed: () => onCopy?.call(context),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                ),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: () => onRetry?.call(context),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
            ],
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(child: body),
    );
  }

  static Widget _skeletonLine(ThemeData theme, {double widthFactor = 1}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
