import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/create_request_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MockRequestRepository _repo() =>
    MockRequestRepository(roomCode: 'DEMO-A101', delay: Duration.zero);

Future<void> _openForm(
  WidgetTester tester,
  MockRequestRepository repo, {
  String? roomCode = 'DEMO-A101',
  VoidCallback? onCreated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CreateRequestScreen(
        repository: repo,
        roomCode: roomCode,
        onCreated: onCreated ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle(); // chờ tải xong loại sự cố
}

/// Điền đủ 3 trường bắt buộc: chọn loại Điện, nhập tiêu đề và mô tả.
Future<void> _fillForm(WidgetTester tester) async {
  await tester.tap(find.text('Điện'));
  await tester.enterText(find.byKey(const Key('titleField')), 'Hỏng quạt');
  await tester.enterText(find.byKey(const Key('descField')), 'Quạt không quay');
  await tester.pumpAndSettle();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Gửi yêu cầu')); // cuộn tới nút
  await tester.tap(find.text('Gửi yêu cầu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'gửi form trống thì báo lỗi 3 trường bắt buộc, không tạo yêu cầu',
    (tester) async {
      final repo = _repo();
      await _openForm(tester, repo);

      await _tapSubmit(tester);

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
    var created = 0;
    await _openForm(tester, repo, onCreated: () => created++);

    await _fillForm(tester);
    await _tapSubmit(tester);

    final list = (await tester.runAsync(() => repo.fetchMyRequests()))!;
    expect(list.length, 3);
    expect(list.first.title, 'Hỏng quạt');
    expect(list.first.status.databaseValue, 'pending');
    expect(list.first.roomCode, 'DEMO-A101'); // phòng lấy từ tài khoản
    expect(created, 1); // màn cha được báo để chuyển về danh sách
  });

  testWidgets('gửi thất bại thì báo lỗi, giữ nguyên form và mở lại nút gửi', (
    tester,
  ) async {
    final repo = _repo()..failCreate = true;
    var created = 0;
    await _openForm(tester, repo, onCreated: () => created++);

    await _fillForm(tester);
    await _tapSubmit(tester);

    expect(find.textContaining('Gửi yêu cầu thất bại'), findsOneWidget);
    expect(find.text('Hỏng quạt'), findsOneWidget); // dữ liệu nhập không mất
    final button = tester.widget<FilledButton>(_submitButton);
    expect(button.onPressed, isNotNull); // được bấm gửi lại
    expect(created, 0);
  });

  testWidgets('tài khoản chưa có phòng thì khóa nút gửi', (tester) async {
    await _openForm(tester, _repo(), roomCode: null);

    final button = tester.widget<FilledButton>(_submitButton);
    expect(button.onPressed, isNull);
    expect(find.textContaining('chưa được gắn phòng'), findsWidgets);
  });
}

/// FilledButton.icon là lớp con của FilledButton nên tìm bằng điều kiện "is".
final _submitButton = find.byWidgetPredicate((w) => w is FilledButton);
