import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/student_confirmation/data/confirmation_repository.dart';
import 'package:dormfix/features/student_confirmation/presentation/awaiting_confirmation_screen.dart';
import 'package:dormfix/features/student_confirmation/presentation/request_confirmation_screen.dart';
import 'package:dormfix/features/student_requests/models/repair_request.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'DF-013: Hiển thị danh sách các yêu cầu Chờ xác nhận của sinh viên',
    (tester) async {
      final repo = MockConfirmationRepository(delay: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(home: AwaitingConfirmationScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Chờ xác nhận'), findsOneWidget);
      expect(find.text('Chờ xác nhận'), findsWidgets);
      expect(find.text('Bình nóng lạnh không vào điện'), findsOneWidget);
      expect(find.text('Bồn rửa mặt bị rỉ nước'), findsOneWidget);
      expect(find.text('DF000004'), findsOneWidget);
      expect(find.text('DF000005'), findsOneWidget);
    },
  );

  testWidgets(
    'DF-013: Hiển thị EmptyView khi không có yêu cầu nào chờ xác nhận',
    (tester) async {
      final repo = MockConfirmationRepository(
        delay: Duration.zero,
        requests: [],
      );
      await tester.pumpWidget(
        MaterialApp(home: AwaitingConfirmationScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Không có yêu cầu nào chờ xác nhận'), findsOneWidget);
    },
  );

  testWidgets(
    'DF-013: Hiển thị ErrorView khi tải dữ liệu thất bại và thử lại thành công',
    (tester) async {
      final repo = MockConfirmationRepository(delay: Duration.zero);
      repo.failFetch = true;

      await tester.pumpWidget(
        MaterialApp(home: AwaitingConfirmationScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Không tải được danh sách. Hãy thử lại.'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsOneWidget);

      repo.failFetch = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();

      expect(find.text('Bình nóng lạnh không vào điện'), findsOneWidget);
    },
  );

  testWidgets(
    'DF-013: Khi nhấn vào thẻ, mở màn hình xác nhận riêng biệt, KHÔNG mở RequestDetailScreen',
    (tester) async {
      final repo = MockConfirmationRepository(delay: Duration.zero);
      await tester.pumpWidget(
        MaterialApp(home: AwaitingConfirmationScreen(repository: repo)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bình nóng lạnh không vào điện'));
      await tester.pumpAndSettle();

      // Mở màn hình xác nhận riêng biệt
      expect(find.byType(RequestConfirmationScreen), findsOneWidget);
      // Tuyệt đối không mở màn hình chi tiết tiến độ thông thường
      expect(find.byType(RequestDetailScreen), findsNothing);
      expect(find.text('Xác nhận hoàn tất'), findsWidgets);
      expect(find.text('Yêu cầu sửa lại'), findsOneWidget);
    },
  );

  testWidgets(
    'DF-013: AdapterConfirmationRepository chỉ lọc các yêu cầu Chờ xác nhận của sinh viên',
    (tester) async {
      final allRequests = [
        RepairRequest(
          id: '1',
          requestCode: 'DF001',
          title: 'Đèn hỏng',
          categoryName: 'Điện',
          roomCode: 'A101',
          status: RepairStatus.pending,
          createdAt: DateTime.now(),
        ),
        RepairRequest(
          id: '2',
          requestCode: 'DF002',
          title: 'Quạt hỏng',
          categoryName: 'Điện',
          roomCode: 'A101',
          status: RepairStatus.awaitingConfirmation,
          createdAt: DateTime.now(),
        ),
      ];

      final mockRepo = MockConfirmationRepository(
        delay: Duration.zero,
        requests: allRequests,
      );

      final result = await mockRepo.fetchAwaitingConfirmationRequests();
      expect(result.length, 1);
      expect(result.first.id, '2');
      expect(result.first.status, RepairStatus.awaitingConfirmation);
    },
  );
}
