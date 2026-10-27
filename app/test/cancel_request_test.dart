import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ===========================================================================
  // Unit tests: kiểm tra điều kiện hủy trong repository (không cần widget)
  // ===========================================================================

  test('cancelRequest thành công khi trạng thái pending', () async {
    // dùng withSamplePending để có pending mock-3
    final pendingRepo = MockRequestRepository.withSamplePending();

    await pendingRepo.cancelRequest(
      requestId: 'mock-3',
      reason: 'Tôi tự sửa được rồi',
    );

    final detail = await pendingRepo.fetchRequestDetail('mock-3');
    expect(detail.request.status.databaseValue, 'cancelled');
    expect(detail.history.last.note, contains('Tôi tự sửa được rồi'));
  });

  test('cancelRequest thành công khi trạng thái assigned', () async {
    final repo = MockRequestRepository(
      roomCode: 'DEMO-A101',
      delay: Duration.zero,
    );
    // mock-2 là assigned
    await repo.cancelRequest(requestId: 'mock-2', reason: 'Không cần nữa');

    final detail = await repo.fetchRequestDetail('mock-2');
    expect(detail.request.status.databaseValue, 'cancelled');
  });

  test('cancelRequest ném lỗi khi trạng thái completed', () async {
    final repo = MockRequestRepository(
      roomCode: 'DEMO-A101',
      delay: Duration.zero,
    );
    // mock-1 là completed
    expect(
      () => repo.cancelRequest(requestId: 'mock-1', reason: 'Lý do'),
      throwsA(isA<Exception>()),
    );
  });

  // ===========================================================================
  // Widget tests: kiểm tra UI nút hủy trong màn hình chi tiết
  // ===========================================================================

  testWidgets('hiển thị nút Hủy khi trạng thái pending', (tester) async {
    final repo = MockRequestRepository.withSamplePending();

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: repo, requestId: 'mock-3'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cancel_outlined), findsWidgets);
    expect(find.text('Hủy yêu cầu này'), findsOneWidget);
  });

  testWidgets('hiển thị nút Hủy khi trạng thái assigned (mock-2)', (
    tester,
  ) async {
    final repo = MockRequestRepository(
      roomCode: 'DEMO-A101',
      delay: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: repo, requestId: 'mock-2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cancel_outlined), findsWidgets);
    expect(find.text('Hủy yêu cầu này'), findsOneWidget);
  });

  testWidgets('không hiển thị nút Hủy khi trạng thái completed (mock-1)', (
    tester,
  ) async {
    final repo = MockRequestRepository(
      roomCode: 'DEMO-A101',
      delay: Duration.zero,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: repo, requestId: 'mock-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
    expect(find.text('Hủy yêu cầu này'), findsNothing);
  });

  testWidgets('bấm Hủy → nhập lý do → xác nhận → trạng thái đổi thành Đã hủy', (
    tester,
  ) async {
    final repo = MockRequestRepository.withSamplePending();

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: repo, requestId: 'mock-3'),
      ),
    );
    await tester.pumpAndSettle();

    // Bấm nút Hủy
    await tester.tap(find.text('Hủy yêu cầu này'));
    await tester.pumpAndSettle();

    // Dialog xuất hiện
    expect(find.text('Hủy yêu cầu'), findsOneWidget);
    expect(find.text('Xác nhận hủy'), findsOneWidget);

    // Nhập lý do
    await tester.enterText(find.byType(TextField), 'Tôi tự sửa được rồi');
    await tester.tap(find.text('Xác nhận hủy'));
    await tester.pumpAndSettle();

    // Kiểm tra trạng thái trong repository đã cập nhật
    final detail = await repo.fetchRequestDetail('mock-3');
    expect(detail.request.status.databaseValue, 'cancelled');
  });

  testWidgets('nhập lý do trống → hiện thông báo lỗi, không hủy', (
    tester,
  ) async {
    final repo = MockRequestRepository.withSamplePending();

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: repo, requestId: 'mock-3'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hủy yêu cầu này'));
    await tester.pumpAndSettle();

    // Bấm xác nhận ngay không nhập lý do
    await tester.tap(find.text('Xác nhận hủy'));
    await tester.pumpAndSettle();

    // Lỗi xuất hiện trong dialog
    expect(find.text('Vui lòng nhập lý do'), findsOneWidget);
    // Yêu cầu chưa bị hủy
    final detail = await repo.fetchRequestDetail('mock-3');
    expect(detail.request.status.databaseValue, 'pending');
  });
}
