import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../vip/vip_style.dart';
import 'admin_dashboard_controller.dart';

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminDashboardController>(
      create: (_) => AdminDashboardController()..loadDashboard(),
      child: const _AdminDashboardBody(),
    );
  }
}

class _AdminDashboardBody extends StatelessWidget {
  const _AdminDashboardBody();

  @override
  Widget build(BuildContext context) {
    final AdminDashboardController controller =
        context.watch<AdminDashboardController>();

    if (controller.loading && controller.recentUsers.isEmpty &&
        controller.errorMessage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.errorMessage != null && controller.recentUsers.isEmpty) {
      return _ErrorState(
        message: controller.errorMessage!,
        onRetry: controller.loadDashboard,
      );
    }

    return RefreshIndicator(
      onRefresh: controller.loadDashboard,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              _Header(loading: controller.loading),
              if (controller.errorMessage != null) ...<Widget>[
                const SizedBox(height: 16),
                _ErrorBanner(
                  message: controller.errorMessage!,
                  onRetry: controller.loadDashboard,
                ),
              ],
              const SizedBox(height: 24),
              _StatsGrid(controller: controller, maxWidth: constraints.maxWidth),
              const SizedBox(height: 32),
              _RecentUsersSection(controller: controller),
              const SizedBox(height: 32),
              _VerificationSection(controller: controller),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Admin Dashboard',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Overview of users, VIP tiers, and verification activity.',
          style: textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        if (loading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.controller,
    required this.maxWidth,
  });

  final AdminDashboardController controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, int> vipCounts = controller.vipCounts;

    final List<_StatCardData> stats = <_StatCardData>[
      _StatCardData(
        title: 'Total users',
        value: controller.totalUsers.toString(),
        icon: Icons.people_alt_rounded,
        description: 'All registered users.',
      ),
      _StatCardData(
        title: 'Pending verifications',
        value: controller.pendingVerifications.toString(),
        icon: Icons.verified_user_outlined,
        description: 'Awaiting review.',
      ),
      _StatCardData(
        title: 'Wallets with balance',
        value: controller.walletsWithBalance.toString(),
        icon: Icons.account_balance_wallet_outlined,
        description:
            'Approx. count from first ${AdminDashboardController.walletSampleLimit} wallets.',
      ),
      _StatCardData(
        title: 'Total reels',
        value: controller.totalReels.toString(),
        icon: Icons.play_circle_outline,
        description: 'Short videos shared by the community.',
      ),
    ];

    final int columns = maxWidth > 960
        ? 3
        : maxWidth > 640
            ? 2
            : 1;
    final double itemWidth = (maxWidth - (16 * (columns - 1))) / columns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: stats
              .map(
                (_StatCardData data) => SizedBox(
                  width: columns == 1 ? double.infinity : itemWidth,
                  child: _StatCard(data: data),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      'VIP tiers',
                      style: theme.textTheme.titleMedium,
                    ),
                    Icon(Icons.military_tech_outlined, color: theme.colorScheme.primary),
                  ],
                ),
                const SizedBox(height: 12),
                ..._vipOrder.map((String tier) {
                  final int count = vipCounts[tier] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: <Widget>[
                        _VipBadge(tier: tier),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${_vipLabel(tier)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          count.toString(),
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const List<String> _vipOrder = <String>['none', 'bronze', 'silver', 'gold', 'platinum'];

String _vipLabel(String tier) {
  switch (tier) {
    case 'bronze':
      return 'Bronze';
    case 'silver':
      return 'Silver';
    case 'gold':
      return 'Gold';
    case 'platinum':
      return 'Platinum';
    default:
      return 'None';
  }
}

class _StatCardData {
  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    this.description,
  });

  final String title;
  final String value;
  final IconData icon;
  final String? description;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});

  final _StatCardData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(data.icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              data.title,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              data.value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (data.description != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                data.description!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentUsersSection extends StatelessWidget {
  const _RecentUsersSection({required this.controller});

  final AdminDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AdminUserSummary> users = controller.recentUsers;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Recent users',
                  style: theme.textTheme.titleMedium,
                ),
                if (controller.loading)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No users yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                ),
              )
            else
              ListView.builder(
                itemCount: users.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (BuildContext context, int index) {
                  final AdminUserSummary user = users[index];
                  return Padding(
                    padding: EdgeInsetsDirectional.only(bottom: index == users.length - 1 ? 0 : 16),
                    child: _RecentUserTile(user: user),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentUserTile extends StatelessWidget {
  const _RecentUserTile({required this.user});

  final AdminUserSummary user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextDirection textDirection =
        Directionality.of(context) ?? TextDirection.ltr;
    final DateFormat dateFormat = DateFormat.yMMMMd();

    final String subtitle = [
      if (user.email != null) user.email!,
      if (user.createdAt != null) 'Joined ${dateFormat.format(user.createdAt!)}',
      if (user.email == null && user.createdAt == null) 'ID: ${user.uid}',
    ].join(' • ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 24,
          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
          backgroundImage:
              user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
          child: user.photoUrl == null
              ? Text(
                  user.displayName.isNotEmpty
                      ? user.displayName.characters.first.toUpperCase()
                      : '?',
                  style: theme.textTheme.titleMedium,
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    user.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (user.vipTier != 'none') _VipBadge(tier: user.vipTier),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        if (textDirection == TextDirection.ltr)
          Icon(Icons.chevron_right, color: theme.disabledColor)
        else
          Icon(Icons.chevron_left, color: theme.disabledColor),
      ],
    );
  }
}

class _VipBadge extends StatelessWidget {
  const _VipBadge({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final VipStyle style = getVipStyle(tier);
    final ThemeData theme = Theme.of(context);

    final Color background = style.nameColor.withOpacity(0.12);
    final Color foreground = style.nameColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.4)),
      ),
      child: Text(
        _vipLabel(tier),
        style: theme.textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VerificationSection extends StatelessWidget {
  const _VerificationSection({required this.controller});

  final AdminDashboardController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Verification requests',
                  style: theme.textTheme.titleMedium,
                ),
                Chip(
                  label: Text('Pending: ${controller.pendingVerifications}'),
                  avatar: const Icon(Icons.watch_later_outlined, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Monitor verification queue and follow up with users awaiting review.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Verification queue coming soon.')),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open verification queue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = theme.colorScheme.errorContainer.withOpacity(0.8);
    final Color foreground = theme.colorScheme.onErrorContainer;

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, color: foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
                  ),
                  TextButton(
                    onPressed: () => onRetry(),
                    style: TextButton.styleFrom(foregroundColor: foreground),
                    child: const Text('Retry'),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => onRetry(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
