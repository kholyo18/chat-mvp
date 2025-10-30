// CODEX-BEGIN:PRIVACY_SETTINGS_PAGE
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'privacy_controller.dart';

class PrivacySettingsPage extends StatelessWidget {
  const PrivacySettingsPage({super.key});

  void _handleError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _wrap(BuildContext context, Future<void> Function() run) async {
    try {
      await run();
    } catch (err) {
      _handleError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PrivacySettingsController>();
    final settings = controller.settings;
    if (controller.loading && settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (settings == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Privacy & Safety')),
        body: const Center(child: Text('Unable to load privacy settings.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(label: 'Direct Messages'),
          const SizedBox(height: 8),
          _SegmentedSettingTile(
            title: 'Who can send you messages',
            description: 'Choose who can start new conversations with you.',
            value: settings.canMessage,
            segments: const [
              ButtonSegment<String>(value: 'everyone', label: Text('Everyone'), icon: Icon(Icons.public)),
              ButtonSegment<String>(value: 'followers', label: Text('Followers'), icon: Icon(Icons.group_rounded)),
              ButtonSegment<String>(value: 'no_one', label: Text('No one'), icon: Icon(Icons.block)),
            ],
            onChanged: (value) => _wrap(context, () => controller.updateCanMessage(value)),
          ),
          const SizedBox(height: 24),
          _SectionTitle(label: 'Visibility'),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: settings.showOnline,
            onChanged: (value) => _wrap(context, () => controller.updateShowOnline(value)),
            title: const Text('Show your online status'),
            subtitle: const Text('When disabled, friends only see your last active time.'),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            value: settings.readReceipts,
            onChanged: (value) => _wrap(context, () => controller.updateReadReceipts(value)),
            title: const Text('Send read receipts'),
            subtitle: const Text('Turning this off hides when you read direct messages.'),
          ),
          const SizedBox(height: 24),
          _SectionTitle(label: 'Stories'),
          const SizedBox(height: 8),
          _SegmentedSettingTile(
            title: 'Story reply permissions',
            description: 'Limit who can reply to your stories.',
            value: settings.allowStoriesReplies,
            segments: const [
              ButtonSegment<String>(value: 'everyone', label: Text('Everyone'), icon: Icon(Icons.public)),
              ButtonSegment<String>(value: 'contacts', label: Text('Contacts'), icon: Icon(Icons.people_alt_rounded)),
              ButtonSegment<String>(value: 'no_one', label: Text('No one'), icon: Icon(Icons.block)),
            ],
            onChanged: (value) => _wrap(context, () => controller.updateAllowStoriesReplies(value)),
          ),
          const SizedBox(height: 24),
          _SectionTitle(label: 'Accessibility'),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: settings.highContrast,
            onChanged: (value) => _wrap(context, () => controller.setHighContrast(value)),
            title: const Text('High contrast mode'),
            subtitle: const Text('Boost contrast across the app for better readability.'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _SegmentedSettingTile extends StatelessWidget {
  const _SegmentedSettingTile({
    required this.title,
    required this.description,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final String title;
  final String description;
  final String value;
  final List<ButtonSegment<String>> segments;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: segments,
          selected: <String>{value},
          onSelectionChanged: (selection) {
            if (selection.isEmpty) {
              return;
            }
            final chosen = selection.first;
            if (chosen != value) {
              onChanged(chosen);
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
        ),
      ],
    );
  }
}
// CODEX-END:PRIVACY_SETTINGS_PAGE
