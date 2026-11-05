import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/presentation/revoke_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-036: MockAdminAccountsRepository', () {
    test(
      'requires a reason and blocks technicians with unfinished work',
      () async {
        const repository = MockAdminAccountsRepository();
        await expectLater(
          repository.revokeAccount(identityCode: 'SV001', reason: '  '),
          throwsA(
            isA<AdminAccountsFailure>().having(
              (failure) => failure.message,
              'message',
              contains('lý do'),
            ),
          ),
        );

        for (final identityCode in ['KTV001', 'KTV002']) {
          await expectLater(
            repository.revokeAccount(
              identityCode: identityCode,
              reason: 'Không còn được phân quyền',
            ),
            throwsA(
              isA<AdminAccountsFailure>().having(
                (failure) => failure.message,
                'message',
                contains('công việc chưa hoàn tất'),
              ),
            ),
          );
        }
      },
    );

    test(
      'allows student with requests and idle technician; keeps account rows',
      () async {
        const repository = MockAdminAccountsRepository();
        await repository.revokeAccount(
          identityCode: 'SV001',
          reason: 'Đã chuyển khỏi ký túc xá',
        );
        final studentRows = await repository.list(
          query: 'SV001',
          offset: 0,
          limit: 10,
        );
        expect(studentRows, hasLength(1));
        expect(studentRows.single.status, AccountStatus.revoked);

        await repository.createTechnician(
          identityCode: 'KTV99001',
          fullName: 'Kỹ thuật viên rảnh',
          email: 'ktv99001@example.com',
          phone: '0912345678',
        );
        await repository.revokeAccount(
          identityCode: 'KTV99001',
          reason: 'Kết thúc hợp đồng',
        );
        final technicianRows = await repository.list(
          query: 'KTV99001',
          role: AppRole.technician,
          offset: 0,
          limit: 10,
        );
        expect(technicianRows, hasLength(1));
        expect(technicianRows.single.status, AccountStatus.revoked);
      },
    );
  });

  testWidgets('requires a reason before submitting the revoke command', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const repository = MockAdminAccountsRepository();
    const account = ManagedAccount(
      fullName: 'Phạm Huy',
      identityCode: 'SV004',
      role: AppRole.student,
      status: AccountStatus.active,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => RevokeAccountDialog.show(
                context,
                repository: repository,
                account: account,
              ),
              child: const Text('Open revoke'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thu hồi'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng nhập lý do thu hồi.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Đã kết thúc lưu trú');
    await tester.tap(find.text('Thu hồi'));
    await tester.pumpAndSettle();

    final rows = await repository.list(query: 'SV004', offset: 0, limit: 10);
    expect(rows.single.status, AccountStatus.revoked);
  });
}
