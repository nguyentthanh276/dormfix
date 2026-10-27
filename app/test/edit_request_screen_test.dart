import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/presentation/edit_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hiển thị nút chỉnh sửa khi yêu cầu ở trạng thái pending', (
    tester,
  ) async {
    final repo = MockRequestRepository.withSamplePending();

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(
          key: const ValueKey('detail-pending'),
          repository: repo,
          requestId: 'mock-3',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Chỉnh sửa yêu cầu này'), findsOneWidget);
  });

  testWidgets(
    'không hiển thị nút chỉnh sửa khi yêu cầu ở trạng thái assigned (mock-2)',
    (tester) async {
      final repo = MockRequestRepository(
        roomCode: 'DEMO-A101',
        delay: Duration.zero,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailScreen(
            key: const ValueKey('detail-assigned'),
            repository: repo,
            requestId: 'mock-2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Chỉnh sửa yêu cầu này'), findsNothing);
    },
  );

  testWidgets('chỉnh sửa tiêu đề, mô tả và lưu thành công (DF-011)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = MockRequestRepository.withSamplePending();
    final detail = await repo.fetchRequestDetail('mock-3');

    bool updatedCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => EditRequestScreen(
              repository: repo,
              detail: detail,
              onUpdated: () => updatedCalled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Kiểm tra dữ liệu cũ đã được điền sẵn
    expect(find.text('Cửa sổ bị kẹt chốt'), findsOneWidget);
    expect(find.text('DEMO-A101'), findsOneWidget);

    // Sửa tiêu đề và mô tả
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cửa sổ bị kẹt chốt'),
      'Cửa sổ phòng bị kẹt chốt đã sửa tiêu đề',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2), // Mô tả chi tiết
      'Mô tả mới đã được cập nhật bởi sinh viên',
    );

    // Bấm lưu
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();

    expect(updatedCalled, isTrue);

    // Kiểm tra lại dữ liệu trong repository
    final refreshed = await repo.fetchRequestDetail('mock-3');
    expect(refreshed.request.title, 'Cửa sổ phòng bị kẹt chốt đã sửa tiêu đề');
    expect(refreshed.description, 'Mô tả mới đã được cập nhật bởi sinh viên');
    expect(
      refreshed.history.last.note,
      'Sinh viên chỉnh sửa thông tin yêu cầu',
    );
  });

  test(
    'updateRequest từ chối cập nhật khi trạng thái không phải pending',
    () async {
      final repo = MockRequestRepository(
        roomCode: 'DEMO-A101',
        delay: Duration.zero,
      );

      // mock-2 là assigned -> ném lỗi
      expect(
        () => repo.updateRequest(
          const EditRepairRequest(
            requestId: 'mock-2',
            title: 'Tiêu đề mới',
            categoryId: 'cat-nuoc',
            description: 'Mô tả mới',
          ),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
}
