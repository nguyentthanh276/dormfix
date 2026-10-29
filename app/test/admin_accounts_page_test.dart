import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/presentation/admin_accounts_page.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AccountsRepository implements AdminAccountsRepository {
  int calls = 0;
  @override
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  }) async {
    calls++;
    return const [];
  }
}

void main() {
  test(
    'demo repository searches without accents and combines filters',
    () async {
      const repository = MockAdminAccountsRepository();
      final matching = await repository.list(
        query: 'nguyen',
        role: AppRole.student,
        status: AccountStatus.active,
        offset: 0,
        limit: 20,
      );
      expect(
        matching.map((account) => account.identityCode),
        contains('SV001'),
      );
      expect(
        matching.every(
          (account) =>
              account.role == AppRole.student &&
              account.status == AccountStatus.active,
        ),
        isTrue,
      );
      final all = await repository.list(query: '', offset: 0, limit: 20);
      expect(all.length, 7);
      expect(
        all.map((account) => account.status).toSet(),
        AccountStatus.values.toSet(),
      );
    },
  );

  test('parses only student and technician account rows', () {
    final account = ManagedAccount.fromJson({
      'full_name': 'Nguyễn An',
      'identity_code': 'SV001',
      'role': 'student',
      'status': 'locked',
    });
    expect(account.role, AppRole.student);
    expect(account.status, AccountStatus.locked);
    expect(
      () => ManagedAccount.fromJson({
        'full_name': 'Root',
        'identity_code': 'ADMIN001',
        'role': 'admin',
        'status': 'active',
      }),
      throwsFormatException,
    );
  });

  testWidgets('blocks the account screen for non-admin users', (tester) async {
    final repository = _AccountsRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(repository: repository, isAdmin: false),
      ),
    );
    expect(
      find.text('Bạn không có quyền truy cập màn hình này.'),
      findsOneWidget,
    );
    expect(repository.calls, 0);
  });

  testWidgets('shows a friendly empty state for an empty account list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(
          repository: _AccountsRepository(),
          isAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa có tài khoản Sinh viên hoặc Kỹ thuật viên nào.'),
      findsOneWidget,
    );
  });

  testWidgets('shows the specified message when a search has no matches', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(
          repository: _AccountsRepository(),
          isAdmin: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'khong co');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy tài khoản phù hợp'), findsOneWidget);
  });
}
