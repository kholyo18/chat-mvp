import 'package:flutter/material.dart';

import '../models/ai_insight.dart';

class AiInsightSheet extends StatelessWidget {
  const AiInsightSheet({super.key, required this.insight});

  final AiInsight insight;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insight.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              insight.summary,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (insight.facts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: insight.facts.entries
                    .map(
                      (entry) => Chip(
                        label: Text('${entry.key}: ${entry.value}'),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
