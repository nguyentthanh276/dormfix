import 'package:dormfix/features/student_requests/data/mock_request_repository.dart';
import 'package:dormfix/features/student_requests/presentation/student_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openShell(WidgetTester tester, {VoidCallback? onSignOut}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StudentShellScreen(
        repository: MockRequestRepository(
          roomCode: 'DEMO-A101',
          delay: Duration.zero,
        ),
        name: 'Nguyễn Văn A',
        roomCode: 'DEMO-A101',
        onSignOut: onSignOut ?? () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mở app vào tab Yêu cầu, có đủ 3 tab ở thanh dưới', (
    tester,
  ) async {
    await _openShell(tester);

    expect(
      find.text('Yêu cầu của tôi'),
      findsOneWidget,
    ); // tiêu đề màn danh sách
    expect(find.text('Vòi nước rò rỉ'), findsOneWidget);
    expect(find.text('Tạo mới'), findsOneWidget);
    expect(find.text('Tài khoản'), findsOneWidget);
  });

  testWidgets(
    'tạo yêu cầu ở tab Tạo mới xong thì về danh sách và thấy yêu cầu mới',
    (tester) async {
      await _openShell(tester);

      await tester.tap(find.text('Tạo mới'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Điện'));
      await tester.enterText(find.byKey(const Key('titleField')), 'Hỏng quạt');
      await tester.enterText(find.byKey(const Key('descField')), 'Không quay');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gửi yêu cầu'));
      await tester.tap(find.text('Gửi yêu cầu'));
      await tester.pumpAndSettle();

      expect(
        find.text('Yêu cầu của tôi'),
        findsOneWidget,
      ); // đã về tab danh sách
      expect(find.text('Hỏng quạt'), findsOneWidget);
      expect(find.text('DF000003'), findsOneWidget);
    },
  );

  testWidgets('tab Tài khoản hiện tên, phòng và nút đăng xuất gọi onSignOut', (
    tester,
  ) async {
    var signedOut = 0;
    await _openShell(tester, onSignOut: () => signedOut++);

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('DEMO-A101'), findsOneWidget);

    await tester.tap(find.text('Đăng xuất'));
    expect(signedOut, 1);
  });
}
