import 'dart:async';

import 'package:dormfix/features/notifications/data/notification_repository.dart';
import 'package:dormfix/features/notifications/models/app_notification.dart';
import 'package:dormfix/features/notifications/presentation/student_notifications_screen.dart';
import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _notification({String message = 'Thông báo kiểm tra'}) =>
    AppNotification(
      id: 'notification-1',
      recipientId: 'student-1',
      requestId: 'mock-2',
      eventType: NotificationEventType.assigned,
      message: message,
      createdAt: DateTime.utc(2026, 11, 3),
    );

class _Repository implements NotificationRepository {
  List<AppNotification> items = [_notification()];
  Future<List<AppNotification>> Function()? fetch;
  Future<void> Function()? mark;
  int marks = 0;

  @override
  Future<List<AppNotification>> fetchNotifications() async =>
      fetch == null ? List.of(items) : await fetch!();

  @override
  Future<int> getUnreadCount() async => items.where((n) => !n.isRead).length;

  @override
  Future<void> markAsRead(String notificationId) async {
    marks++;
    await mark?.call();
    items = items.map((n) => n.copyWith(readAt: DateTime.now())).toList();
  }

  @override
  Future<void> markAllAsRead() async {
    marks++;
    await mark?.call();
    items = items.map((n) => n.copyWith(readAt: DateTime.now())).toList();
  }
}

Widget _screen(_Repository repository) => MaterialApp(
  home: StudentNotificationsScreen(
    notificationRepository: repository,
    requestRepository: MockRequestRepository(delay: Duration.zero),
  ),
);

void main() {
  testWidgets('failed single read stays unread and does not navigate', (
    tester,
  ) async {
    final repository = _Repository()
      ..mark = () async => throw Exception('network');
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thông báo kiểm tra'));
    await tester.pumpAndSettle();
    expect(repository.marks, 1);
    expect(find.byType(RequestDetailScreen), findsNothing);
    expect(find.byTooltip('Đánh dấu tất cả đã đọc'), findsOneWidget);
    expect(
      find.text('Không thể mở thông báo. Vui lòng thử lại.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending read prevents duplicate writes and navigation', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _Repository()..mark = () => pending.future;
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thông báo kiểm tra'));
    await tester.pump();
    await tester.tap(find.text('Thông báo kiểm tra'));
    expect(repository.marks, 1);
    expect(find.byType(RequestDetailScreen), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RequestDetailScreen), findsOneWidget);
  });

  testWidgets('refresh response cannot undo acknowledged mark-all state', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(_screen(repository));
    await tester.pumpAndSettle();
    final pending = Completer<List<AppNotification>>();
    repository.fetch = () => pending.future;
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Đánh dấu tất cả đã đọc'));
    await tester.pump();
    pending.complete([_notification()]);
    await tester.pumpAndSettle();
    expect(repository.marks, 1);
    expect(find.byTooltip('Đánh dấu tất cả đã đọc'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repository replacement invalidates a pending open action', (
    tester,
  ) async {
    final pending = Completer<void>();
    final oldRepository = _Repository()..mark = () => pending.future;
    await tester.pumpWidget(_screen(oldRepository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thông báo kiểm tra'));
    await tester.pump();
    final newRepository = _Repository()
      ..items = [_notification(message: 'Thông báo của phiên mới')];
    await tester.pumpWidget(_screen(newRepository));
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RequestDetailScreen), findsNothing);
    expect(find.text('Thông báo của phiên mới'), findsOneWidget);
    expect(find.text('Thông báo kiểm tra'), findsNothing);
  });

  testWidgets('fallback notification repository survives closing the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyRequestsScreen(
          repository: MockRequestRepository(delay: Duration.zero),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsOneWidget);
    await tester.tap(find.byTooltip('Thông báo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Đánh dấu tất cả đã đọc'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsNothing);
  });
}
