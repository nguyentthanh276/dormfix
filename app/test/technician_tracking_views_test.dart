import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/technician_jobs/data/technician_tracking_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_tracking.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_tracking_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

final _date = DateTime.utc(2026, 11, 3, 8);

TechnicianWorkHistoryEntry _history({bool current = false}) =>
    TechnicianWorkHistoryEntry(
      assignmentId: current ? 'current-assignment' : 'former-assignment',
      requestId: current ? 'job-1' : null,
      requestCode: current ? 'DF000001' : 'DF000002',
      title: current ? 'Công việc còn quyền xem' : 'Tiêu đề lúc được giao',
      roomCode: 'A101',
      assignedAt: _date,
      endedAt: current ? null : _date.add(const Duration(hours: 1)),
      status: current ? RepairStatus.completed : null,
      canOpenDetail: current,
    );

TechnicianNotification _notification({bool current = false}) =>
    TechnicianNotification(
      id: 'notification-1',
      eventType: current ? 'assigned' : 'transferred_out',
      message: current
          ? 'Bạn được giao công việc.'
          : 'Công việc đã chuyển giao.',
      createdAt: _date,
      readAt: null,
      requestId: current ? 'job-1' : null,
      canOpenDetail: current,
    );

class _TrackingRepository implements TechnicianTrackingRepository {
  List<TechnicianWorkHistoryEntry> history = [];
  List<TechnicianNotification> notifications = [];
  Future<List<TechnicianWorkHistoryEntry>> Function()? loadHistory;
  Future<List<TechnicianNotification>> Function()? loadNotifications;
  Future<DateTime> Function()? markRead;
  int readCalls = 0;

  @override
  Future<List<TechnicianWorkHistoryEntry>> fetchWorkHistory() async =>
      loadHistory == null ? history : await loadHistory!();

  @override
  Future<List<TechnicianNotification>> fetchNotifications() async =>
      loadNotifications == null ? notifications : await loadNotifications!();

  @override
  Future<DateTime> markNotificationRead(String notificationId) async {
    readCalls++;
    return markRead == null ? _date : await markRead!();
  }
}

void main() {
  testWidgets('former assignments remain summary-only; current work can open', (
    tester,
  ) async {
    final repository = _TrackingRepository()
      ..history = [_history(), _history(current: true)];
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TechnicianWorkHistoryView(
            repository: repository,
            onOpenDetail: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiêu đề lúc được giao'));
    expect(opened, isEmpty);
    expect(
      find.text('Đã kết thúc phân công · Chỉ xem tóm tắt'),
      findsOneWidget,
    );
    expect(find.text('Xem chi tiết công việc'), findsOneWidget);
    await tester.tap(find.text('Công việc còn quyền xem'));
    expect(opened, ['job-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transferred notification marks read without opening details', (
    tester,
  ) async {
    final repository = _TrackingRepository()..notifications = [_notification()];
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TechnicianNotificationsView(
            repository: repository,
            onOpenDetail: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Công việc đã chuyển giao.'));
    await tester.pumpAndSettle();
    expect(repository.readCalls, 1);
    expect(opened, isEmpty);
    expect(find.textContaining('· Đã đọc'), findsOneWidget);
    expect(
      find.text('Bạn không còn quyền mở chi tiết công việc này.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'notification waits for read receipt and prevents duplicate taps',
    (tester) async {
      final receipt = Completer<DateTime>();
      final repository = _TrackingRepository()
        ..notifications = [_notification(current: true)]
        ..markRead = () => receipt.future;
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TechnicianNotificationsView(
              repository: repository,
              onOpenDetail: opened.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bạn được giao công việc.'));
      await tester.pump();
      await tester.tap(find.text('Bạn được giao công việc.'));
      expect(repository.readCalls, 1);
      expect(opened, isEmpty);
      receipt.complete(_date);
      await tester.pumpAndSettle();
      expect(opened, ['job-1']);
    },
  );

  testWidgets(
    'late history response cannot restore data after session expiry',
    (tester) async {
      final auth = TechnicianTestAuthRepository();
      final pending = Completer<List<TechnicianWorkHistoryEntry>>();
      final tracking = _TrackingRepository()
        ..loadHistory = () => pending.future;
      try {
        await tester.pumpWidget(
          DormFixApp(
            authRepository: auth,
            technicianJobsRepository: TechnicianTestJobsRepository(),
            technicianTrackingRepository: tracking,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('technician-tracking-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lịch sử công việc'));
        await tester.pump();
        auth.hasSession = false;
        await tester.pumpAndSettle();
        pending.complete([_history()]);
        await tester.pumpAndSettle();
        expect(find.text('Tiêu đề lúc được giao'), findsNothing);
        expect(find.byType(TechnicianWorkHistoryView), findsNothing);
        expect(find.text('Đăng nhập'), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await auth.dispose();
      }
    },
  );

  testWidgets('delayed refresh cannot undo a confirmed read receipt', (
    tester,
  ) async {
    final repository = _TrackingRepository()..notifications = [_notification()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TechnicianNotificationsView(
            repository: repository,
            onOpenDetail: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final refresh = Completer<List<TechnicianNotification>>();
    repository.loadNotifications = () => refresh.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.tap(find.byTooltip('Đánh dấu đã đọc'));
    await tester.pump();
    refresh.complete([_notification()]);
    await tester.pumpAndSettle();
    expect(find.textContaining('· Đã đọc'), findsOneWidget);
    expect(find.byTooltip('Đánh dấu đã đọc'), findsNothing);
  });

  testWidgets(
    'denied list refresh invalidates pending notification navigation',
    (tester) async {
      final receipt = Completer<DateTime>();
      final repository = _TrackingRepository()
        ..notifications = [_notification(current: true)]
        ..markRead = () => receipt.future;
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TechnicianNotificationsView(
              repository: repository,
              onOpenDetail: opened.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bạn được giao công việc.'));
      await tester.pump();
      repository.loadNotifications = () async =>
          throw const TechnicianTrackingFailure(
            'Không còn quyền.',
            accessDenied: true,
          );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      receipt.complete(_date);
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.text('Không còn quyền.'), findsOneWidget);
      expect(find.text('Bạn được giao công việc.'), findsNothing);
    },
  );
}
