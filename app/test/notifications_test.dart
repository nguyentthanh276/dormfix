import 'package:dormfix/features/notifications/data/mock_notification_repository.dart';
import 'package:dormfix/features/notifications/models/app_notification.dart';
import 'package:dormfix/features/notifications/presentation/student_notifications_screen.dart';
import 'package:dormfix/features/student_confirmation/presentation/request_confirmation_screen.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-017: Unit test AppNotification & MockNotificationRepository', () {
    test('AppNotification isRead getter hoạt động đúng', () {
      final unread = AppNotification(
        id: '1',
        recipientId: 'u1',
        requestId: 'r1',
        eventType: NotificationEventType.assigned,
        message: 'Thông báo 1',
        createdAt: DateTime.now(),
        readAt: null,
      );
      expect(unread.isRead, isFalse);

      final read = unread.copyWith(readAt: DateTime.now());
      expect(read.isRead, isTrue);
    });

    test('NotificationEventType fromDb và toDb mapping chính xác', () {
      expect(
        NotificationEventType.fromDb('repair_reported'),
        NotificationEventType.repairReported,
      );
      expect(NotificationEventType.repairReported.toDb(), 'repair_reported');
      expect(
        NotificationEventType.fromDb('unknown_event'),
        NotificationEventType.other,
      );
    });

    test('fetchNotifications sắp xếp thông báo mới nhất lên đầu', () async {
      final oldNotif = AppNotification(
        id: 'old',
        recipientId: 'u1',
        requestId: 'r1',
        eventType: NotificationEventType.completed,
        message: 'Cũ',
        createdAt: DateTime(2026, 1, 1),
      );
      final newNotif = AppNotification(
        id: 'new',
        recipientId: 'u1',
        requestId: 'r2',
        eventType: NotificationEventType.assigned,
        message: 'Mới',
        createdAt: DateTime(2026, 1, 2),
      );

      final repo = MockNotificationRepository(
        delay: Duration.zero,
        notifications: [oldNotif, newNotif],
      );

      final list = await repo.fetchNotifications();
      expect(list.first.id, 'new');
      expect(list.last.id, 'old');
    });

    test('markAsRead cập nhật readAt và giảm unread count', () async {
      final notif = AppNotification(
        id: 'notif-test',
        recipientId: 'u1',
        requestId: 'r1',
        eventType: NotificationEventType.assigned,
        message: 'Test',
        createdAt: DateTime.now(),
      );
      final repo = MockNotificationRepository(
        delay: Duration.zero,
        notifications: [notif],
      );

      expect(await repo.getUnreadCount(), 1);
      await repo.markAsRead('notif-test');
      expect(await repo.getUnreadCount(), 0);

      final list = await repo.fetchNotifications();
      expect(list.first.isRead, isTrue);
    });

    test('markAllAsRead cập nhật tất cả thông báo về đã đọc', () async {
      final n1 = AppNotification(
        id: '1',
        recipientId: 'u1',
        requestId: 'r1',
        eventType: NotificationEventType.assigned,
        message: '1',
        createdAt: DateTime.now(),
      );
      final n2 = AppNotification(
        id: '2',
        recipientId: 'u1',
        requestId: 'r2',
        eventType: NotificationEventType.completed,
        message: '2',
        createdAt: DateTime.now(),
      );
      final repo = MockNotificationRepository(
        delay: Duration.zero,
        notifications: [n1, n2],
      );

      expect(await repo.getUnreadCount(), 2);
      await repo.markAllAsRead();
      expect(await repo.getUnreadCount(), 0);

      final list = await repo.fetchNotifications();
      expect(list.every((n) => n.isRead), isTrue);
    });
  });

  group('DF-017: Widget test StudentNotificationsScreen', () {
    testWidgets('Hiển thị danh sách thông báo và các nhãn sự kiện', (
      tester,
    ) async {
      final notifRepo = MockNotificationRepository(delay: Duration.zero);
      final reqRepo = MockRequestRepository(delay: Duration.zero);

      await tester.pumpWidget(
        MaterialApp(
          home: StudentNotificationsScreen(
            notificationRepository: notifRepo,
            requestRepository: reqRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('Đã sửa xong'), findsOneWidget);
      expect(find.text('Đã phân công'), findsOneWidget);
      expect(
        find.textContaining('Bình nóng lạnh không vào điện'),
        findsOneWidget,
      );
      expect(find.textContaining('Vòi nước rò rỉ'), findsOneWidget);
    });

    testWidgets('Bấm Đánh dấu tất cả đã đọc thì cập nhật toàn bộ trạng thái', (
      tester,
    ) async {
      final notifRepo = MockNotificationRepository(delay: Duration.zero);
      final reqRepo = MockRequestRepository(delay: Duration.zero);

      await tester.pumpWidget(
        MaterialApp(
          home: StudentNotificationsScreen(
            notificationRepository: notifRepo,
            requestRepository: reqRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nút đánh dấu tất cả đã đọc xuất hiện khi có thông báo chưa đọc
      final markAllBtn = find.byIcon(Icons.done_all_rounded);
      expect(markAllBtn, findsOneWidget);

      await tester.tap(markAllBtn);
      await tester.pumpAndSettle();

      expect(await notifRepo.getUnreadCount(), 0);
      expect(find.text('Đã đánh dấu tất cả là đã đọc'), findsOneWidget);
    });

    testWidgets(
      'Bấm vào thông báo sửa xong -> mở màn hình xác nhận nghiệm thu (DF-013)',
      (tester) async {
        final notifRepo = MockNotificationRepository(delay: Duration.zero);
        final reqRepo = MockRequestRepository(delay: Duration.zero);

        await tester.pumpWidget(
          MaterialApp(
            home: StudentNotificationsScreen(
              notificationRepository: notifRepo,
              requestRepository: reqRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Bấm vào thông báo "Đã sửa xong"
        await tester.tap(find.textContaining('Bình nóng lạnh không vào điện'));
        await tester.pumpAndSettle();

        // Mở màn hình xác nhận nghiệm thu riêng
        expect(find.byType(RequestConfirmationScreen), findsOneWidget);
      },
    );

    testWidgets(
      'Bấm vào thông báo đã phân công -> mở màn hình chi tiết yêu cầu (DF-010)',
      (tester) async {
        final notifRepo = MockNotificationRepository(delay: Duration.zero);
        final reqRepo = MockRequestRepository(delay: Duration.zero);

        await tester.pumpWidget(
          MaterialApp(
            home: StudentNotificationsScreen(
              notificationRepository: notifRepo,
              requestRepository: reqRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Bấm vào thông báo "Đã phân công"
        await tester.tap(find.textContaining('Vòi nước rò rỉ'));
        await tester.pumpAndSettle();

        // Mở màn hình chi tiết yêu cầu
        expect(find.byType(RequestDetailScreen), findsOneWidget);
      },
    );

    testWidgets('Hiển thị EmptyView khi không có thông báo nào', (
      tester,
    ) async {
      final notifRepo = MockNotificationRepository(
        delay: Duration.zero,
        notifications: [],
      );
      final reqRepo = MockRequestRepository(delay: Duration.zero);

      await tester.pumpWidget(
        MaterialApp(
          home: StudentNotificationsScreen(
            notificationRepository: notifRepo,
            requestRepository: reqRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bạn chưa có thông báo nào'), findsOneWidget);
    });

    testWidgets('Hiển thị ErrorView khi tải lỗi và nút Thử lại', (
      tester,
    ) async {
      final notifRepo = MockNotificationRepository(delay: Duration.zero);
      notifRepo.failFetch = true;
      final reqRepo = MockRequestRepository(delay: Duration.zero);

      await tester.pumpWidget(
        MaterialApp(
          home: StudentNotificationsScreen(
            notificationRepository: notifRepo,
            requestRepository: reqRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Không thể tải thông báo. Hãy thử lại.'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsOneWidget);

      notifRepo.failFetch = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Đã sửa xong'), findsOneWidget);
    });
  });

  group('DF-017: Tích hợp với MyRequestsScreen', () {
    testWidgets(
      'MyRequestsScreen có biểu tượng chuông thông báo và mở đúng màn hình',
      (tester) async {
        final notifRepo = MockNotificationRepository(delay: Duration.zero);
        final reqRepo = MockRequestRepository(delay: Duration.zero);

        await tester.pumpWidget(
          MaterialApp(
            home: MyRequestsScreen(
              repository: reqRepo,
              notificationRepository: notifRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Kiểm tra có biểu tượng thông báo
        final notifBtn = find.byTooltip('Thông báo');
        expect(notifBtn, findsOneWidget);

        // Bấm mở màn hình thông báo
        await tester.tap(notifBtn);
        await tester.pumpAndSettle();

        expect(find.byType(StudentNotificationsScreen), findsOneWidget);
      },
    );
  });
}
