import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/presentation/reset_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-038: MockAdminAccountsRepository', () {
    test(
      'resets existing student and technician, forcing password change',
      () async {
        const repository = MockAdminAccountsRepository();
        final studentBefore = await repository.list(
          query: 'SV001',
          offset: 0,
          limit: 1,
        );
        final student = await repository.resetPassword(identityCode: 'SV001');
        expect(student.identityCode, 'SV001');
        expect(student.temporaryPassword.length, greaterThanOrEqualTo(6));
        expect(student.mustChangePassword, isTrue);
        expect(studentBefore, hasLength(1));

        final technician = await repository.resetPassword(
          identityCode: 'KTV002',
        );
        expect(technician.identityCode, 'KTV002');
        expect(technician.role, 'technician');
        expect(technician.status, 'locked');
        expect(technician.mustChangePassword, isTrue);
      },
    );

    test('rejects unknown and admin accounts', () async {
      const repository = MockAdminAccountsRepository();
      await expectLater(
        repository.resetPassword(identityCode: 'MISSING'),
        throwsA(isA<AdminAccountsFailure>()),
      );
      await expectLater(
        repository.resetPassword(identityCode: 'ADMIN001'),
        throwsA(isA<AdminAccountsFailure>()),
      );
    });
  });

  testWidgets('shows only the new temporary password after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const repository = MockAdminAccountsRepository();
    const account = ManagedAccount(
      fullName: 'Nguyễn An',
      identityCode: 'SV001',
      role: AppRole.student,
      status: AccountStatus.active,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => ResetPasswordDialog.show(
                context,
                repository: repository,
                account: account,
              ),
              child: const Text('Open reset'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open reset'));
    await tester.pumpAndSettle();
    expect(find.text('Đặt lại mật khẩu?'), findsOneWidget);
    expect(find.text('Mật khẩu cũ'), findsNothing);

    await tester.tap(find.text('Cấp mật khẩu tạm'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu tạm mới'), findsOneWidget);
    expect(
      find.text(
        'Khi đăng nhập, người dùng phải đổi mật khẩu trước khi sử dụng hệ thống.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SelectableText), findsOneWidget);
    final temporaryPassword = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(temporaryPassword, isNotEmpty);
    expect(find.text('Hoàn tất'), findsOneWidget);
  });
}
