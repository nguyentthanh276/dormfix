import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/my_requests_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockRequestRepository _repo() =>
    MockRequestRepository(roomCode: 'DEMO-A101', delay: Duration.zero);

Future<void> _openList(WidgetTester tester, MockRequestRepository repo) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MyRequestsPage(
        repository: repo,
        roomCode: 'DEMO-A101',
        onSignOut: () {},
      ),
    ),
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

    expect(find.textContaining('OLD-B202'), findsOneWidget);
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

  testWidgets('tạo yêu cầu mới xong thì danh sách có thêm yêu cầu đó', (
    tester,
  ) async {
    await _openList(tester, _repo());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tạo yêu cầu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('titleField')), 'Hỏng quạt');
    await tester.tap(find.byKey(const Key('categoryField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Điện').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('descField')), 'Không quay');
    await tester.ensureVisible(find.text('Gửi yêu cầu')); // cuộn tới nút
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    expect(find.text('Hỏng quạt'), findsOneWidget); // đã quay về và tải lại
    expect(find.text('DF000003'), findsOneWidget);
  });
}
