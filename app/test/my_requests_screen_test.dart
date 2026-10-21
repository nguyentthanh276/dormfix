import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockRequestRepository _repo() =>
    MockRequestRepository(roomCode: 'DEMO-A101', delay: Duration.zero);

Future<void> _openList(WidgetTester tester, MockRequestRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(home: MyRequestsScreen(repository: repo)),
  );
}

void main() {
  testWidgets('đang tải thì hiện vòng quay, tải xong hiện danh sách', (
    tester,
  ) async {
    await _openList(tester, _repo());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
    expect(find.text('DF000002'), findsOneWidget);
  });

  testWidgets('yêu cầu gửi từ phòng cũ vẫn hiển thị kèm phòng cũ', (
    tester,
  ) async {
    await _openList(tester, _repo());
    await tester.pumpAndSettle();

    expect(find.text('OLD-B202'), findsOneWidget);
  });

  testWidgets('lỗi tải thì báo lỗi, bấm Thử lại thì tải được', (tester) async {
    final repo = _repo()..failFetch = true;
    await _openList(tester, repo);
    await tester.pumpAndSettle();

    expect(find.textContaining('Không tải được danh sách'), findsOneWidget);

    repo.failFetch = false; // mạng ổn lại
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
    expect(find.textContaining('Không tải được danh sách'), findsNothing);
  });

  testWidgets('bấm nhãn trạng thái thì chỉ còn yêu cầu đúng trạng thái đó', (
    tester,
  ) async {
    await _openList(tester, _repo());
    await tester.pumpAndSettle();
    expect(find.text('Vòi nước rò rỉ'), findsOneWidget); // Đã phân công
    expect(find.text('Bóng đèn phòng bị cháy'), findsOneWidget); // Hoàn tất

    await tester.tap(find.text('Hoàn tất (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Bóng đèn phòng bị cháy'), findsOneWidget);
    expect(find.text('Vòi nước rò rỉ'), findsNothing);

    await tester.tap(find.text('Tất cả (2)')); // bỏ lọc
    await tester.pumpAndSettle();
    expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
  });
}
