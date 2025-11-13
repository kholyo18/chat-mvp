import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ai_insight.dart';

class AiInsightSheet extends StatelessWidget {
  const AiInsightSheet({
    super.key,
    required this.insight,
    required this.isLoading,
    required this.onRetry,
    this.onTranslate,
    this.onExplain,
    this.onRelated,
    this.onAskAi,
  });

  final AiInsight? insight;
  final bool isLoading;
  final VoidCallback onRetry;
  final VoidCallback? onTranslate;
  final VoidCallback? onExplain;
  final VoidCallback? onRelated;
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context) {
    final hasData = insight != null && insight!.hasContent;
    return SafeArea(
      top: false,
      child: Padding(
        padding: MediaQuery.of(context).viewInsets,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(entity: insight?.entity, isLoading: isLoading),
              const SizedBox(height: 16),
              if (isLoading)
                const _InsightSkeleton()
              else if (hasData)
                _InsightContent(
                  insight: insight!,
                  onTranslate: onTranslate,
                  onExplain: onExplain,
                  onRelated: onRelated,
                )
              else
                _FallbackContent(onRetry: onRetry, onAskAi: onAskAi),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.entity, required this.isLoading});

  final String? entity;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: isLoading
              ? const _SkeletonLine(width: double.infinity)
              : Text(
                  entity == null || entity!.isEmpty ? 'تحليل سريع' : entity!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'AI',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _InsightContent extends StatelessWidget {
  const _InsightContent({
    required this.insight,
    this.onTranslate,
    this.onExplain,
    this.onRelated,
  });

  final AiInsight insight;
  final VoidCallback? onTranslate;
  final VoidCallback? onExplain;
  final VoidCallback? onRelated;

  bool get _canOpenMap => insight.type.toLowerCase() == 'place';

  @override
  Widget build(BuildContext context) {
    final facts = insight.facts.entries.toList();
    final hasFacts = facts.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryCard(bullets: insight.bullets),
        if (hasFacts) ...[
          const SizedBox(height: 12),
          _FactsGrid(facts: facts),
        ],
        const SizedBox(height: 16),
        _ActionRow(
          onTranslate: onTranslate,
          onExplain: onExplain,
          onRelated: onRelated,
          onOpenMap: _canOpenMap
              ? () => _launchMap(insight.entity)
              : null,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.bullets});

  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: bullets.isNotEmpty
              ? bullets
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(
                            child: Text(
                              line,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList()
              : [
                  Text(
                    'لا يوجد ملخص سريع.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
        ),
      ),
    );
  }
}

class _FactsGrid extends StatelessWidget {
  const _FactsGrid({required this.facts});

  final List<MapEntry<String, String>> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width.isFinite ? (width - 12) / 2 : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: facts.map((entry) {
            return SizedBox(
              width: itemWidth,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(entry.value, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    this.onTranslate,
    this.onExplain,
    this.onOpenMap,
    this.onRelated,
  });

  final VoidCallback? onTranslate;
  final VoidCallback? onExplain;
  final VoidCallback? onOpenMap;
  final VoidCallback? onRelated;

  @override
  Widget build(BuildContext context) {
    final actions = <_ActionConfig>[
      _ActionConfig('ترجمة', Icons.translate_rounded, onTranslate),
      _ActionConfig('شرح', Icons.lightbulb_outline, onExplain),
      if (onOpenMap != null)
        _ActionConfig('خريطة', Icons.map_outlined, onOpenMap),
      _ActionConfig('ذات صلة', Icons.compass_calibration_outlined, onRelated),
    ].where((action) => action.onTap != null).toList();
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: actions
          .map(
            (action) => OutlinedButton.icon(
              onPressed: action.onTap,
              icon: Icon(action.icon, size: 18),
              label: Text(action.label),
            ),
          )
          .toList(),
    );
  }
}

class _ActionConfig {
  _ActionConfig(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
}

class _InsightSkeleton extends StatelessWidget {
  const _InsightSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        _SkeletonLine(width: double.infinity),
        SizedBox(height: 12),
        _SkeletonLine(width: double.infinity),
        SizedBox(height: 12),
        _SkeletonLine(width: double.infinity),
      ],
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: 16,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _FallbackContent extends StatelessWidget {
  const _FallbackContent({required this.onRetry, this.onAskAi});

  final VoidCallback onRetry;
  final VoidCallback? onAskAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'لا توجد حقائق سريعة لهذه الرسالة.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton(
              onPressed: onAskAi ?? onRetry,
              child: const Text('اسأل الذكاء الاصطناعي'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _launchMap(String query) async {
  final encoded = Uri.encodeComponent(query);
  final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
