import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/models/edit_repair_request.dart';
import 'package:dormfix/features/student_requests/models/new_repair_request.dart';
import 'package:dormfix/features/student_requests/presentation/edit_request_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockRequestRepository _repo() =>
    MockRequestRepository(roomCode: 'DEMO-A101', delay: Duration.zero);

void main() {
  testWidgets('hiển thị nút chỉnh sửa khi yêu cầu ở trạng thái pending', (
    tester,
  ) async {
    final repo = _repo();

    // Tạo yêu cầu pending bên ngoài widget tree (không cần timer giả)
    final created = await repo.createRequest(
      const NewRepairRequest(
        title: 'Cửa sổ bị kẹt chốt',
        categoryId: 'cat-noithat',
        description: 'Chốt cửa bị gỉ sét không đóng được',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(
          key: const ValueKey('detail-pending'),
          repository: repo,
          requestId: created.id,
        ),
      ),
    );

    // runAsync chạy Future.delayed thật (không fake timer)
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.text('Chỉnh sửa yêu cầu này'), findsOneWidget);
  });

  testWidgets(
    'không hiển thị nút chỉnh sửa khi yêu cầu ở trạng thái assigned (mock-2)',
    (tester) async {
      final repo = _repo();
      await tester.pumpWidget(
        MaterialApp(
          home: RequestDetailScreen(
            key: const ValueKey('detail-assigned'),
            repository: repo,
            requestId: 'mock-2',
          ),
        ),
      );

      await tester.runAsync(() => Future.delayed(Duration.zero));
      await tester.pump();

      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('Chỉnh sửa yêu cầu này'), findsNothing);
    },
  );

  testWidgets('chỉnh sửa tiêu đề, mô tả và lưu thành công (DF-011)', (
    tester,
  ) async {
    final repo = _repo();
    final created = await repo.createRequest(
      const NewRepairRequest(
        title: 'Cửa sổ phòng bị kẹt chốt',
        categoryId: 'cat-noithat',
        description: 'Mô tả ban đầu',
      ),
    );
    final detail = await repo.fetchRequestDetail(created.id);

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
    await tester.pump();

    // Kiểm tra dữ liệu cũ đã được điền sẵn
    expect(find.text('Cửa sổ phòng bị kẹt chốt'), findsOneWidget);
    expect(find.text('DEMO-A101'), findsOneWidget);

    // Sửa tiêu đề và mô tả
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cửa sổ phòng bị kẹt chốt'),
      'Cửa sổ phòng bị kẹt chốt đã sửa tiêu đề',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2), // Mô tả chi tiết
      'Mô tả mới đã được cập nhật bởi sinh viên',
    );

    // Bấm lưu — updateRequest là async, dùng runAsync
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.runAsync(() => Future.delayed(Duration.zero));
    await tester.pump();

    expect(updatedCalled, isTrue);

    // Kiểm tra lại dữ liệu trong repository
    final refreshed = await repo.fetchRequestDetail(created.id);
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
      final repo = _repo();

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
