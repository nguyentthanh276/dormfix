import 'dart:async';

import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/notifications/data/mock_notification_repository.dart';
import 'package:dormfix/features/notifications/models/app_notification.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/models/request_detail.dart';
import 'package:dormfix/features/student_requests/presentation/create_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:dormfix/features/student_requests/presentation/student_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotificationRequests extends MockRequestRepository {
  _NotificationRequests() : super(delay: Duration.zero);

  @override
  Future<RequestDetail> fetchRequestDetail(String requestId) async {
    if (requestId != 'rejected-request') {
      return super.fetchRequestDetail(requestId);
    }
    return RequestDetail(
      request: RepairRequest(
        id: requestId,
        requestCode: 'DF000303',
        title: 'Yêu cầu thiếu mô tả',
        categoryName: 'Điện',
        roomCode: 'A101',
        status: RepairStatus.rejected,
        createdAt: DateTime.utc(2026, 11, 10),
      ),
      description: 'Chi tiết chính chủ của yêu cầu bị từ chối',
      history: const [],
    );
  }
}

class _NotificationInbox extends MockNotificationRepository {
  _NotificationInbox(List<AppNotification> items) : super(notifications: items);
  Completer<int>? nextCount;

  @override
  Future<int> getUnreadCount() {
    final pending = nextCount;
    nextCount = null;
    return pending?.future ?? super.getUnreadCount();
  }
}

String? _notificationBadge(WidgetTester tester) {
  final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
  final destination = navigation.destinations[2] as NavigationDestination;
  final icon = navigation.selectedIndex == 2
      ? destination.selectedIcon
      : destination.icon;
  return icon is Badge ? (icon.label as Text?)?.data : null;
}

Future<void> _openShell(WidgetTester tester, {VoidCallback? onSignOut}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StudentShellScreen(
        repository: MockRequestRepository(
          roomCode: 'DEMO-A101',
          delay: Duration.zero,
        ),
        name: 'Nguyễn Văn A',
        roomCode: 'DEMO-A101',
        onSignOut: onSignOut ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'assigned and rejected notifications open the right request and refresh the unread badge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final assigned = AppNotification(
        id: 'notification-assigned',
        recipientId: 'current-student',
        requestId: 'mock-2',
        eventType: NotificationEventType.assigned,
        message: 'DF000002 đã được phân công.',
        createdAt: DateTime.utc(2026, 11, 10, 8),
      );
      final rejected = AppNotification(
        id: 'notification-rejected',
        recipientId: 'current-student',
        requestId: 'rejected-request',
        eventType: NotificationEventType.rejected,
        message: 'DF000303 bị từ chối vì thiếu mô tả.',
        createdAt: DateTime.utc(2026, 11, 10, 9),
      );
      final items = [assigned, rejected];
      final notifications = _NotificationInbox(items);
      await tester.pumpWidget(
        MaterialApp(
          home: StudentShellScreen(
            repository: _NotificationRequests(),
            name: 'Sinh viên A',
            roomCode: 'A101',
            onSignOut: () {},
            notificationRepository: notifications,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_notificationBadge(tester), '2');

      final oldCount = Completer<int>();
      notifications.nextCount = oldCount;
      await tester.tap(find.text('Thông báo'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(rejected.message)).dy,
        lessThan(tester.getTopLeft(find.text(assigned.message)).dy),
      );

      await tester.tap(find.text(assigned.message));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RequestDetailScreen>(find.byType(RequestDetailScreen))
            .requestId,
        assigned.requestId,
      );
      expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      oldCount.complete(2);
      await tester.pumpAndSettle();
      expect(_notificationBadge(tester), '1');

      await tester.tap(find.text(rejected.message));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RequestDetailScreen>(find.byType(RequestDetailScreen))
            .requestId,
        rejected.requestId,
      );
      expect(find.text('Yêu cầu thiếu mô tả'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(_notificationBadge(tester), isNull);

      final arrived = assigned.copyWith(
        id: 'new-notification',
        message: 'Có phân công mới khi hộp thông báo đang mở.',
        createdAt: DateTime.utc(2026, 11, 10, 10),
      );
      items.add(arrived);
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();
      expect(find.text(arrived.message), findsOneWidget);
      expect(_notificationBadge(tester), '1');
      await tester.tap(find.text('Đánh dấu tất cả đã đọc'));
      await tester.pumpAndSettle();
      expect(_notificationBadge(tester), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'root has four destinations and one header without a back button',
    (tester) async {
      await _openShell(tester);

      expect(
        find.text('Yêu cầu của tôi'),
        findsOneWidget,
      ); // tiêu đề màn danh sách
      expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(4),
      );
      expect(find.text('Yêu cầu'), findsOneWidget);
      expect(find.text('Chờ xác nhận'), findsOneWidget);
      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('Cá nhân'), findsOneWidget);
      expect(find.text('Tạo mới'), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    },
  );

  testWidgets(
    'create action opens a page without tabs and success refreshes the list',
    (tester) async {
      await _openShell(tester);

      await tester.tap(find.byKey(const Key('student-create-request')));
      await tester.pumpAndSettle();
      expect(find.byType(CreateRequestScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.text('Điện'));
      await tester.enterText(find.byKey(const Key('titleField')), 'Hỏng quạt');
      await tester.enterText(find.byKey(const Key('descField')), 'Không quay');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gửi yêu cầu'));
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();

      expect(
        find.text('Yêu cầu của tôi'),
        findsOneWidget,
      ); // đã về tab danh sách
      expect(find.text('Hỏng quạt'), findsOneWidget);
      expect(find.text('DF000003'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );

  testWidgets('personal tab shows profile and logout calls onSignOut', (
    tester,
  ) async {
    var signedOut = 0;
    await _openShell(tester, onSignOut: () => signedOut++);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('DEMO-A101'), findsOneWidget);

    await tester.tap(find.text('Đăng xuất'));
    expect(signedOut, 1);
  });

  testWidgets('request filter is retained while tabs refresh on activation', (
    tester,
  ) async {
    await _openShell(tester);
    await tester.tap(find.text('Hoàn tất (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Vòi nước rò rỉ'), findsNothing);

    await tester.tap(find.text('Thông báo'));
    await tester.pumpAndSettle();
    expect(find.text('Đánh dấu tất cả đã đọc'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);

    await tester.tap(find.text('Yêu cầu'));
    await tester.pumpAndSettle();
    expect(find.text('Bóng đèn phòng bị cháy'), findsOneWidget);
    expect(find.text('Vòi nước rò rỉ'), findsNothing);
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('Hoàn tất (1)'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('detail hides tabs and back restores the request filter', (
    tester,
  ) async {
    await _openShell(tester);
    await tester.tap(find.text('Hoàn tất (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bóng đèn phòng bị cháy'));
    await tester.pumpAndSettle();
    expect(find.byType(RequestDetailScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Bóng đèn phòng bị cháy'), findsOneWidget);
    expect(find.text('Vòi nước rò rỉ'), findsNothing);
  });

  testWidgets(
    'unfinished create form asks before leaving for app and system back',
    (tester) async {
      await _openShell(tester);
      await tester.tap(find.byKey(const Key('student-create-request')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('titleField')),
        'Nội dung chưa gửi',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Bỏ yêu cầu đang nhập?'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Nội dung chưa gửi'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Bỏ yêu cầu đang nhập?'), findsOneWidget);
      await tester.tap(find.text('Bỏ thay đổi'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateRequestScreen), findsNothing);
      expect(find.text('Yêu cầu của tôi'), findsOneWidget);
      expect(find.text('Nội dung chưa gửi'), findsNothing);
    },
  );

  testWidgets('all student destinations fit a 320px phone', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openShell(tester);
    for (final tab in ['Chờ xác nhận', 'Thông báo', 'Cá nhân', 'Yêu cầu']) {
      final destination = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(tab),
      );
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
      expect(find.byType(AppBar), findsOneWidget);
    }
  });
}
