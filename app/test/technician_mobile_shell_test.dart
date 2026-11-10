import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/core/widgets/dormfix_app_bar.dart';
import 'package:dormfix/core/widgets/role_navigation_bar.dart';
import 'package:dormfix/features/profile/presentation/active_change_password_page.dart';
import 'package:dormfix/features/technician_jobs/data/technician_tracking_repository.dart';
import 'package:dormfix/features/technician_jobs/models/technician_tracking.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

class _Tracking implements TechnicianTrackingRepository {
  int historyCalls = 0;
  int notificationCalls = 0;

  @override
  Future<List<TechnicianWorkHistoryEntry>> fetchWorkHistory() async {
    historyCalls++;
    return [
      TechnicianWorkHistoryEntry(
        assignmentId: 'assignment-1',
        requestId: 'job-1',
        requestCode: 'DF000001',
        title: 'Công việc trong lịch sử',
        roomCode: 'A101',
        assignedAt: technicianTestDate,
        endedAt: null,
        status: RepairStatus.awaitingRework,
        canOpenDetail: true,
      ),
    ];
  }

  @override
  Future<List<TechnicianNotification>> fetchNotifications() async {
    notificationCalls++;
    return [
      TechnicianNotification(
        id: 'notification-1',
        eventType: 'assigned',
        message: 'Có công việc được giao',
        createdAt: technicianTestDate,
        readAt: technicianTestDate,
        requestId: 'job-1',
        canOpenDetail: true,
      ),
    ];
  }

  @override
  Future<DateTime> markNotificationRead(String notificationId) async =>
      technicianTestDate;
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(RoleNavigationBar),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('job list scroll survives tab changes and detail Back', (
    tester,
  ) async {
    final auth = TechnicianTestAuthRepository();
    final jobs = TechnicianTestJobsRepository()
      ..jobs = List.generate(
        15,
        (index) =>
            technicianJob(id: 'job-$index', title: 'Công việc số $index'),
      );
    try {
      await tester.pumpWidget(
        DormFixApp(authRepository: auth, technicianJobsRepository: jobs),
      );
      await tester.pumpAndSettle();
      final jobList = find.byKey(const Key('technician-jobs-list'));
      await tester.drag(jobList, const Offset(0, -450));
      await tester.pumpAndSettle();
      double offset() => tester.widget<ListView>(jobList).controller!.offset;
      final savedOffset = offset();
      expect(savedOffset, greaterThan(100));
      await _tab(tester, 'Cá nhân');
      await _tab(tester, 'Công việc');
      expect(offset(), savedOffset);
      final tile = find
          .descendant(of: jobList, matching: find.byType(InkWell))
          .hitTestable()
          .first;
      final detailOffset = offset();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(offset(), detailOffset);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.dispose();
    }
  });

  testWidgets('320px tabs load lazily and preserve the selected job filter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = TechnicianTestAuthRepository();
    final tracking = _Tracking();
    final jobs = TechnicianTestJobsRepository()
      ..jobs = [
        technicianJob(),
        technicianJob(
          id: 'job-2',
          title: 'Công việc đang xử lý',
          status: RepairStatus.inProgress,
        ),
      ];
    try {
      await tester.pumpWidget(
        DormFixApp(
          authRepository: auth,
          technicianJobsRepository: jobs,
          technicianTrackingRepository: tracking,
        ),
      );
      await tester.pumpAndSettle();
      expect(tracking.historyCalls, 0);
      expect(tracking.notificationCalls, 0);
      expect(find.byType(DormFixAppBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      final filter = find.widgetWithText(ChoiceChip, 'Đang xử lý (1)');
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
      await _tab(tester, 'Lịch sử');
      expect(tracking.historyCalls, 1);
      await _tab(tester, 'Thông báo');
      expect(tracking.notificationCalls, 1);
      await _tab(tester, 'Cá nhân');
      expect(find.text('Kỹ thuật viên Bình'), findsOneWidget);
      await _tab(tester, 'Công việc');
      expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
      expect(find.text('Công việc đang xử lý'), findsOneWidget);
      expect(find.text('Vòi nước phòng A101 rò rỉ'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.dispose();
    }
  });

  for (final label in ['Lịch sử', 'Thông báo']) {
    testWidgets('detail opened from $label hides tabs and Back restores it', (
      tester,
    ) async {
      final auth = TechnicianTestAuthRepository();
      final tracking = _Tracking();
      try {
        await tester.pumpWidget(
          DormFixApp(
            authRepository: auth,
            technicianJobsRepository: TechnicianTestJobsRepository(),
            technicianTrackingRepository: tracking,
          ),
        );
        await tester.pumpAndSettle();
        await _tab(tester, label);
        await tester.tap(
          find.text(
            label == 'Lịch sử'
                ? 'Công việc trong lịch sử'
                : 'Có công việc được giao',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(RoleNavigationBar), findsNothing);
        expect(find.text('Chi tiết công việc'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<RoleNavigationBar>(find.byType(RoleNavigationBar))
              .selectedIndex,
          label == 'Lịch sử' ? 1 : 2,
        );
        expect(
          label == 'Lịch sử'
              ? tracking.historyCalls
              : tracking.notificationCalls,
          2,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await auth.dispose();
      }
    });
  }

  testWidgets('password form hides tabs and disappears with session expiry', (
    tester,
  ) async {
    final auth = TechnicianTestAuthRepository();
    try {
      await tester.pumpWidget(
        DormFixApp(
          authRepository: auth,
          technicianJobsRepository: TechnicianTestJobsRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dormfix-account-menu')));
      await tester.pumpAndSettle();
      final changePassword = find.byKey(
        const Key('profile-change-password-btn'),
      );
      await tester.scrollUntilVisible(
        changePassword,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(changePassword),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(changePassword);
      await tester.pumpAndSettle();
      expect(find.byType(ActiveChangePasswordPage), findsOneWidget);
      expect(find.byType(RoleNavigationBar), findsNothing);
      auth.hasSession = false;
      await tester.pumpAndSettle();
      expect(find.byType(ActiveChangePasswordPage), findsNothing);
      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RoleNavigationBar), findsNothing);
      expect(find.byType(ActiveChangePasswordPage), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await auth.dispose();
    }
  });
}
