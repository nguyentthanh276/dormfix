import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/presentation/restore_account_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-037: MockAdminAccountsRepository', () {
    test(
      'student restore requires an active room and retains the same row',
      () async {
        const repository = MockAdminAccountsRepository();
        final before = await repository.list(
          query: 'SV003',
          offset: 0,
          limit: 10,
        );
        expect(before, hasLength(1));
        expect(before.single.status, AccountStatus.revoked);

        await expectLater(
          repository.restoreAccount(identityCode: 'SV003'),
          throwsA(isA<AdminAccountsFailure>()),
        );
        await expectLater(
          repository.restoreAccount(identityCode: 'SV003', roomId: 'room-4'),
          throwsA(isA<AdminAccountsFailure>()),
        );

        await repository.restoreAccount(
          identityCode: 'SV003',
          roomId: 'room-2',
        );
        final after = await repository.list(
          query: 'SV003',
          offset: 0,
          limit: 10,
        );
        expect(after, hasLength(1));
        expect(after.single.identityCode, before.single.identityCode);
        expect(after.single.status, AccountStatus.active);
        final details = await repository.getStudentForEdit('SV003');
        expect(details.roomId, 'room-2');
      },
    );

    test(
      'technician restores without a room and rejects invalid state',
      () async {
        const repository = MockAdminAccountsRepository();
        await repository.restoreAccount(identityCode: 'KTV003');
        final restored = await repository.list(
          query: 'KTV003',
          role: AppRole.technician,
          offset: 0,
          limit: 10,
        );
        expect(restored, hasLength(1));
        expect(restored.single.status, AccountStatus.active);

        await expectLater(
          repository.restoreAccount(identityCode: 'KTV003'),
          throwsA(isA<AdminAccountsFailure>()),
        );
        await expectLater(
          repository.restoreAccount(identityCode: 'KTV002'),
          throwsA(isA<AdminAccountsFailure>()),
        );
      },
    );
  });

  testWidgets('student restore requires an explicit active room choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const repository = MockAdminAccountsRepository();
    const account = ManagedAccount(
      fullName: 'Lê Cường',
      identityCode: 'SV003',
      role: AppRole.student,
      status: AccountStatus.revoked,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => RestoreAccountDialog.show(
                context,
                repository: repository,
                account: account,
              ),
              child: const Text('Open restore'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khôi phục'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng chọn phòng đang hoạt động.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A2-305 (Tòa A)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khôi phục'));
    await tester.pumpAndSettle();

    final accountRows = await repository.list(
      query: 'SV003',
      offset: 0,
      limit: 10,
    );
    expect(accountRows.single.status, AccountStatus.active);
    expect((await repository.getStudentForEdit('SV003')).roomId, 'room-2');
  });
}
