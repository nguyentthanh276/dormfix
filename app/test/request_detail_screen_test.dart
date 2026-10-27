import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_screen.dart';
import 'package:dormfix/features/student_requests/presentation/request_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockRequestRepository _repo() =>
    MockRequestRepository(roomCode: 'DEMO-A101', delay: Duration.zero);

void main() {
  testWidgets('bấm thẻ ở danh sách thì mở chi tiết đúng yêu cầu + timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MyRequestsScreen(repository: _repo())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vòi nước rò rỉ'));
    await tester.pumpAndSettle();

    expect(find.text('Tiến trình xử lý'), findsOneWidget);
    expect(find.text('Sinh viên gửi yêu cầu'), findsOneWidget);
    expect(find.textContaining('Lê Văn Cường'), findsWidgets);
  });

  testWidgets('lỗi tải chi tiết thì báo lỗi, bấm Thử lại thì tải được', (
    tester,
  ) async {
    final repo = _repo()..failFetch = true;
    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: repo, requestId: 'mock-2'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Không tải được chi tiết'), findsOneWidget);

    repo.failFetch = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(find.text('Tiến trình xử lý'), findsOneWidget);
  });

  testWidgets('hiển thị ảnh đính kèm từ sinh viên và mở dialog xem ảnh', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: _repo(), requestId: 'mock-2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ảnh đính kèm từ sinh viên'), findsOneWidget);
    expect(find.text('anh_voi_nuoc_ro_ri_1.jpg'), findsOneWidget);

    // Bấm xem ảnh
    await tester.tap(find.text('anh_voi_nuoc_ro_ri_1.jpg'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Tệp: anh_voi_nuoc_ro_ri_1.jpg'),
      findsOneWidget,
    );

    // Đóng dialog
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tệp: anh_voi_nuoc_ro_ri_1.jpg'), findsNothing);
  });

  testWidgets('hiển thị kết quả sửa chữa từ kỹ thuật viên (DF-026/DF-010)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: RequestDetailScreen(repository: _repo(), requestId: 'mock-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kết quả sửa chữa'), findsOneWidget);
    expect(find.textContaining('Đã thay mới bóng đèn LED 18W'), findsOneWidget);
    expect(find.text('anh_nghiem_thu_sua_chua.jpg'), findsOneWidget);
  });
}
