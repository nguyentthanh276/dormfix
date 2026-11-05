import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/presentation/edit_student_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-033: MockAdminAccountsRepository', () {
    test(
      'updates student details and current room without changing code',
      () async {
        const repository = MockAdminAccountsRepository();
        final before = await repository.getStudentForEdit('SV001');
        expect(before.roomId, 'room-1');

        await repository.updateStudent(
          identityCode: 'SV001',
          fullName: 'Nguyễn An mới',
          phone: '0912345678',
          roomId: 'room-3',
        );

        final after = await repository.getStudentForEdit('SV001');
        expect(after.fullName, 'Nguyễn An mới');
        expect(after.phone, '0912345678');
        expect(after.roomId, 'room-3');
        expect(after.roomCode, 'B1-112');
        final accounts = await repository.list(
          query: 'SV001',
          offset: 0,
          limit: 10,
        );
        expect(accounts.single.identityCode, 'SV001');
      },
    );

    test('requires a valid phone and active room', () async {
      const repository = MockAdminAccountsRepository();
      await expectLater(
        repository.updateStudent(
          identityCode: 'SV001',
          fullName: 'Nguyễn An',
          phone: '123',
          roomId: 'room-1',
        ),
        throwsA(isA<AdminAccountsFailure>()),
      );
      await expectLater(
        repository.updateStudent(
          identityCode: 'SV001',
          fullName: 'Nguyễn An',
          phone: '0912345678',
          roomId: 'room-4',
        ),
        throwsA(isA<AdminAccountsFailure>()),
      );
      await expectLater(
        repository.getStudentForEdit('SV003'),
        throwsA(isA<AdminAccountsFailure>()),
      );
    });
  });

  testWidgets('edit form keeps identity immutable and saves phone and room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const repository = MockAdminAccountsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => EditStudentDialog.show(
                context,
                repository: repository,
                identityCode: 'SV001',
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.text('SV001'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Email đăng nhập không thể thay đổi.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Họ và tên *'),
      'Nguyễn An cập nhật',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Số điện thoại *'),
      '+84912345678',
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B1-112 (Tòa B)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();

    final updated = await repository.getStudentForEdit('SV001');
    expect(updated.fullName, 'Nguyễn An cập nhật');
    expect(updated.phone, '+84912345678');
    expect(updated.roomId, 'room-3');
  });
}
