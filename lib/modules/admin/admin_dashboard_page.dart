// CODEX-BEGIN:ADMIN_DASHBOARD_PAGE
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/firestore_service.dart';
import 'admin_dashboard_controller.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({
    super.key,
    required this.uid,
    required this.isAdmin,
  });

  final String? uid;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminDashboardController>(
      create: (_) => AdminDashboardController(
        firestoreService: FirestoreService(),
        currentUid: uid,
        isAdmin: isAdmin,
      )..guardedInit(),
      child: const _AdminDashboardView(),
    );
  }
}

class _AdminDashboardView extends StatelessWidget {
  const _AdminDashboardView();

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminDashboardController>();
    final metrics = controller.metrics;
    final bool showLoading = controller.loading && metrics == null;

    Widget buildBody() {
      if (!controller.allowAccess) {
        return EmptyErrorView(
          message: controller.errorMessage ?? 'هذه الصفحة متاحة للمشرفين فقط.',
          onRetry: controller.refresh,
        );
      }
      if (showLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (controller.errorMessage != null && metrics == null) {
        return EmptyErrorView(
          message: controller.errorMessage!,
          onRetry: controller.refresh,
        );
      }
      if (metrics == null) {
        return EmptyErrorView(
          message: 'تعذر تحميل البيانات، حاول مرة أخرى.',
          onRetry: controller.refresh,
        );
      }

      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MetricsGrid(metrics: metrics, refreshing: controller.loading),
            const SizedBox(height: 24),
            _ReportsSection(
              controller: controller,
              onResolve: (report) async {
                try {
                  await controller.resolveReport(report.id);
                  _showSnack(context, 'تم تعليم البلاغ كمُعالج.');
                } catch (err) {
                  _showSnack(context, err.toString());
                }
              },
              onBlockUser: (report) async {
                final targetId = report.targetId;
                if (targetId == null || targetId.isEmpty) {
                  _showSnack(context, 'لا يوجد معرف مستخدم لحظره.');
                  return;
                }
                try {
                  await controller.softBlockUser(targetId);
                  _showSnack(context, 'تم تقييد المستخدم بنجاح.');
                } catch (err) {
                  _showSnack(context, err.toString());
                }
              },
              onDeleteStory: (report) async {
                final storyId = report.storyId ?? report.targetId;
                if (storyId == null || storyId.isEmpty) {
                  _showSnack(context, 'لا يوجد معرف قصة لحذفها.');
                  return;
                }
                try {
                  await controller.deleteStory(storyId);
                  _showSnack(context, 'تم تعليم القصة كمحذوفة.');
                } catch (err) {
                  _showSnack(context, err.toString());
                }
              },
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة')),
      body: buildBody(),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.metrics,
    required this.refreshing,
  });

  final AdminDashboardData metrics;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final items = [
      _MetricData(
        label: 'مستخدمون نشطون (٢٤س)',
        value: metrics.activeUsers24h.toString(),
        icon: Icons.people_alt_rounded,
      ),
      _MetricData(
        label: 'القصص المنشورة (٢٤س)',
        value: metrics.stories24h.toString(),
        icon: Icons.history_edu_rounded,
      ),
      _MetricData(
        label: 'بلاغات قيد الانتظار',
        value: metrics.pendingReports.toString(),
        icon: Icons.report_problem_rounded,
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final item in items)
          _MetricCard(
            data: item,
            refreshing: refreshing,
          ),
      ],
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.data,
    required this.refreshing,
  });

  final _MetricData data;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(data.icon, size: 32),
              const SizedBox(height: 12),
              Text(
                data.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                data.label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (refreshing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({
    required this.controller,
    required this.onResolve,
    required this.onBlockUser,
    required this.onDeleteStory,
  });

  final AdminDashboardController controller;
  final Future<void> Function(AdminReportItem report) onResolve;
  final Future<void> Function(AdminReportItem report) onBlockUser;
  final Future<void> Function(AdminReportItem report) onDeleteStory;

  @override
  Widget build(BuildContext context) {
    final reports = controller.reports;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'البلاغات المعلقة',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (reports.isEmpty && controller.loadingMore)
          const Center(child: CircularProgressIndicator())
        else if (reports.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.inbox_rounded, size: 48, color: Colors.green),
                  SizedBox(height: 12),
                  Text('لا توجد بلاغات حالية.'),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final report = reports[index];
              return _ReportTile(
                report: report,
                onTap: () => _showReportSheet(
                  context,
                  report,
                  onResolve,
                  onBlockUser,
                  onDeleteStory,
                ),
              );
            },
          ),
        if (controller.loadMoreError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton.icon(
              onPressed: controller.loadingMore ? null : () => controller.loadMore(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text('تعذر تحميل المزيد: ${controller.loadMoreError}'),
            ),
          ),
        if (controller.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton.icon(
              onPressed: controller.loadingMore ? null : () => controller.loadMore(),
              icon: controller.loadingMore
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_downward_rounded),
              label: Text(controller.loadingMore ? 'جاري التحميل...' : 'تحميل المزيد'),
            ),
          ),
      ],
    );
  }

  void _showReportSheet(
    BuildContext context,
    AdminReportItem report,
    Future<void> Function(AdminReportItem report) onResolve,
    Future<void> Function(AdminReportItem report) onBlockUser,
    Future<void> Function(AdminReportItem report) onDeleteStory,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        bool working = false;
        final dateFormat = DateFormat('y/M/d HH:mm');
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> run(Future<void> Function() action) async {
              if (working) return;
              setState(() => working = true);
              try {
                await action();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              } catch (err) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err.toString())),
                );
                setState(() => working = false);
              }
            }

            final storyTarget = report.storyId ?? report.targetId;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'تفاصيل البلاغ',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'المعرف', value: report.id),
                  if (report.reason.isNotEmpty)
                    _InfoRow(label: 'السبب', value: report.reason),
                  if (report.targetType != null)
                    _InfoRow(label: 'النوع', value: report.targetType!),
                  if (report.targetId != null)
                    _InfoRow(label: 'المعرف المستهدف', value: report.targetId!),
                  if (report.reportedBy != null)
                    _InfoRow(label: 'المبلّغ', value: report.reportedBy!),
                  if (report.createdAt != null)
                    _InfoRow(
                      label: 'التاريخ',
                      value: dateFormat.format(report.createdAt!.toLocal()),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: working ? null : () => run(() => onResolve(report)),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('وضع علامة كمعالج'),
                  ),
                  if ((report.targetId ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: working ? null : () => run(() => onBlockUser(report)),
                        icon: const Icon(Icons.person_off_rounded),
                        label: const Text('تقييد المستخدم'),
                      ),
                    ),
                  if (storyTarget != null && storyTarget.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        onPressed: working ? null : () => run(() => onDeleteStory(report)),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('حذف القصة'),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.report,
    required this.onTap,
  });

  final AdminReportItem report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('y/M/d HH:mm');
    final subtitle = [
      if (report.reason.isNotEmpty) report.reason,
      if (report.createdAt != null)
        dateFormat.format(report.createdAt!.toLocal()),
    ].join(' • ');
    return Card(
      child: ListTile(
        leading: const Icon(Icons.report_rounded, color: Colors.orange),
        title: Text(report.targetId ?? report.id),
        subtitle: Text(subtitle.isEmpty ? 'بلاغ بدون تفاصيل' : subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class EmptyErrorView extends StatelessWidget {
  const EmptyErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 52, color: Colors.orange),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ),
        ],
      ),
    );
  }
}
// CODEX-END:ADMIN_DASHBOARD_PAGE
