// CODEX-BEGIN:ADMIN_DASHBOARD_CONTROLLER
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/firestore_service.dart';

class AdminDashboardController extends ChangeNotifier {
  AdminDashboardController({
    required this.firestoreService,
    required this.currentUid,
    required this.isAdmin,
  });

  final FirestoreService firestoreService;
  final String? currentUid;
  final bool isAdmin;

  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  String? errorMessage;
  String? loadMoreError;
  AdminDashboardData? metrics;
  final List<AdminReportItem> reports = <AdminReportItem>[];

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  bool get allowAccess => isAdmin && (currentUid?.isNotEmpty ?? false);

  Future<void> guardedInit({bool force = false}) async {
    if (!allowAccess) {
      errorMessage = 'هذه الصفحة متاحة للمشرفين فقط.';
      loading = false;
      notifyListeners();
      return;
    }
    if (loading && !force) {
      return;
    }
    loading = true;
    errorMessage = null;
    notifyListeners();
    const int maxAttempts = 3;
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt += 1;
      try {
        final SafeResult<AdminDashboardData> result = await firestoreService
            .fetchAdminDashboard(uid: currentUid!)
            .timeout(const Duration(seconds: 8));
        if (result is SafeFailure<AdminDashboardData>) {
          throw Exception(result.message);
        }
        metrics = (result as SafeSuccess<AdminDashboardData>).value;
        final bool reportsLoaded = await _loadReports(reset: true);
        if (!reportsLoaded && reports.isEmpty) {
          errorMessage = loadMoreError;
        }
        loading = false;
        notifyListeners();
        return;
      } on TimeoutException catch (_) {
        if (attempt >= maxAttempts) {
          errorMessage = 'انتهت مهلة تحميل لوحة الإدارة. حاول مرة أخرى.';
          loading = false;
          notifyListeners();
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      } catch (err) {
        errorMessage = err.toString();
        loading = false;
        notifyListeners();
        return;
      }
    }
  }

  Future<void> refresh() async {
    await guardedInit(force: true);
  }

  Future<bool> _loadReports({required bool reset}) async {
    if (!allowAccess) {
      return false;
    }
    if (loadingMore) {
      return true;
    }
    if (reset) {
      reports.clear();
      _lastDoc = null;
      hasMore = true;
      loadMoreError = null;
    }
    loadingMore = true;
    notifyListeners();

    final SafeResult<AdminReportsPage> result = await firestoreService
        .fetchPendingReportsPage(
      uid: currentUid!,
      startAfter: reset ? null : _lastDoc,
      limit: 20,
    );

    bool success = false;
    if (result is SafeSuccess<AdminReportsPage>) {
      final AdminReportsPage page = result.value;
      if (reset) {
        reports
          ..clear()
          ..addAll(page.reports);
      } else {
        reports.addAll(page.reports);
      }
      _lastDoc = page.lastDocument;
      hasMore = page.hasMore;
      loadMoreError = null;
      success = true;
    } else if (result is SafeFailure<AdminReportsPage>) {
      loadMoreError = result.message;
      if (reset) {
        hasMore = false;
      }
    }

    loadingMore = false;
    notifyListeners();
    return success;
  }

  Future<void> loadMore() async {
    if (!allowAccess || !hasMore) {
      return;
    }
    await _loadReports(reset: false);
  }

  Future<void> resolveReport(String reportId) async {
    if (!allowAccess) {
      throw Exception('ليس لديك صلاحية الوصول الإدارية.');
    }
    final SafeResult<void> result = await firestoreService.resolveReport(
      uid: currentUid!,
      reportId: reportId,
    );
    if (result is SafeFailure<void>) {
      throw Exception(result.message);
    }
    reports.removeWhere((AdminReportItem item) => item.id == reportId);
    if (metrics != null) {
      final int pending = metrics!.pendingReports - 1;
      metrics = metrics!.copyWith(pendingReports: pending < 0 ? 0 : pending);
    }
    notifyListeners();
    if (reports.isEmpty && hasMore) {
      await loadMore();
    }
  }

  Future<void> softBlockUser(String targetUid) async {
    if (!allowAccess) {
      throw Exception('ليس لديك صلاحية الوصول الإدارية.');
    }
    final SafeResult<void> result = await firestoreService.softBlockUser(
      uid: currentUid!,
      targetUid: targetUid,
    );
    if (result is SafeFailure<void>) {
      throw Exception(result.message);
    }
  }

  Future<void> deleteStory(String storyId) async {
    if (!allowAccess) {
      throw Exception('ليس لديك صلاحية الوصول الإدارية.');
    }
    final SafeResult<void> result = await firestoreService.deleteStory(
      uid: currentUid!,
      storyId: storyId,
    );
    if (result is SafeFailure<void>) {
      throw Exception(result.message);
    }
    if (metrics != null) {
      final int stories = metrics!.stories24h - 1;
      metrics = metrics!.copyWith(stories24h: stories < 0 ? 0 : stories);
      notifyListeners();
    }
  }
}
// CODEX-END:ADMIN_DASHBOARD_CONTROLLER
