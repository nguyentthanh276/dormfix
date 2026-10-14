import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/create_request_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockRequestRepository _repo() =>
    MockRequestRepository(roomCode: 'DEMO-A101', delay: Duration.zero);

Future<void> _openForm(
  WidgetTester tester,
  MockRequestRepository repo, {
  String? roomCode = 'DEMO-A101',
}) async {
  // Mở form bằng Navigator.push từ một trang gốc, giống app thật,
  // để sau khi gửi xong form có route để pop về.
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<bool>(
                builder: (_) =>
                    CreateRequestPage(repository: repo, roomCode: roomCode),
              ),
            ),
            child: const Text('mở form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở form'));
  await tester.pumpAndSettle(); // chờ chuyển trang và tải xong loại sự cố
}

void main() {
  testWidgets(
    'gửi form trống thì báo lỗi 3 trường bắt buộc, không tạo yêu cầu',
    (tester) async {
      final repo = _repo();
      await _openForm(tester, repo);

      await tester.ensureVisible(find.text('Gửi yêu cầu')); // cuộn tới nút
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập tiêu đề'), findsOneWidget);
      expect(find.text('Vui lòng chọn loại sự cố'), findsOneWidget);
      expect(find.text('Vui lòng nhập mô tả'), findsOneWidget);
      // runAsync: trong testWidgets đồng hồ là giả, Future.delayed chỉ chạy được qua runAsync.
      final list = await tester.runAsync(() => repo.fetchMyRequests());
      expect(list!.length, 2); // vẫn chỉ có 2 yêu cầu mẫu
    },
  );

  testWidgets('điền đủ và gửi thì tạo yêu cầu mới ở Chờ tiếp nhận', (
    tester,
  ) async {
    final repo = _repo();
    await _openForm(tester, repo);

    await tester.enterText(find.byKey(const Key('titleField')), 'Hỏng quạt');
    await tester.tap(find.byKey(const Key('categoryField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Điện').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('descField')),
      'Quạt không quay',
    );

    await tester.ensureVisible(find.text('Gửi yêu cầu')); // cuộn tới nút
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    final list = (await tester.runAsync(() => repo.fetchMyRequests()))!;
    expect(list.length, 3);
    expect(list.first.title, 'Hỏng quạt');
    expect(list.first.status.databaseValue, 'pending');
    expect(list.first.roomCode, 'DEMO-A101'); // phòng lấy từ tài khoản
  });

  testWidgets('gửi thất bại thì báo lỗi, giữ nguyên form và mở lại nút gửi', (
    tester,
  ) async {
    final repo = _repo()..failCreate = true;
    await _openForm(tester, repo);

    await tester.enterText(find.byKey(const Key('titleField')), 'Hỏng quạt');
    await tester.tap(find.byKey(const Key('categoryField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Điện').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('descField')), 'Không quay');
    await tester.ensureVisible(find.text('Gửi yêu cầu')); // cuộn tới nút
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Gửi yêu cầu thất bại'), findsOneWidget);
    expect(find.text('Hỏng quạt'), findsOneWidget); // dữ liệu nhập không mất
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull); // được bấm gửi lại
  });

  testWidgets('tài khoản chưa có phòng thì khóa nút gửi', (tester) async {
    await _openForm(tester, _repo(), roomCode: null);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.textContaining('chưa được gắn phòng'), findsWidgets);
  });
}
