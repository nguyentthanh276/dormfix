import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/presentation/admin_accounts_page.dart';
import 'package:dormfix/features/admin_accounts/presentation/create_technician_dialog.dart';
import 'package:dormfix/features/admin_accounts/presentation/edit_student_dialog.dart';
import 'package:dormfix/features/admin_accounts/presentation/restore_account_dialog.dart';
import 'package:dormfix/features/admin_accounts/presentation/reset_password_dialog.dart';
import 'package:dormfix/features/admin_rooms/models/admin_room.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AccountsRepository implements AdminAccountsRepository {
  _AccountsRepository({this.accounts = const []});

  final List<ManagedAccount> accounts;
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
    return accounts.skip(offset).take(limit).toList();
  }

  @override
  Future<CreatedStudentResult> createStudent({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    required String roomId,
    String? temporaryPassword,
  }) async {
    return CreatedStudentResult(
      id: 'test-id',
      identityCode: identityCode,
      fullName: fullName,
      email: email,
      phone: phone,
      role: 'student',
      status: 'active',
      mustChangePassword: true,
      temporaryPassword: temporaryPassword ?? 'DF@123456',
      roomId: roomId,
      roomCode: 'A1-101',
      roomBuilding: 'Tòa A',
    );
  }

  @override
  Future<CreatedTechnicianResult> createTechnician({
    required String identityCode,
    required String fullName,
    required String email,
    required String phone,
    String? temporaryPassword,
  }) async {
    return CreatedTechnicianResult(
      id: 'test-technician-id',
      identityCode: identityCode,
      fullName: fullName,
      email: email,
      phone: phone,
      status: 'active',
      mustChangePassword: true,
      temporaryPassword: temporaryPassword ?? 'DF@123456',
    );
  }

  @override
  Future<StudentAccountEditDetails> getStudentForEdit(
    String identityCode,
  ) async {
    return const StudentAccountEditDetails(
      fullName: 'Nguyễn An',
      phone: '0912345678',
      roomId: 'r1',
      roomCode: 'A1-101',
      roomBuilding: 'Tòa A',
    );
  }

  @override
  Future<void> updateStudent({
    required String identityCode,
    required String fullName,
    required String phone,
    required String roomId,
  }) async {}

  @override
  Future<void> revokeAccount({
    required String identityCode,
    required String reason,
  }) async {}

  @override
  Future<void> restoreAccount({
    required String identityCode,
    String? roomId,
  }) async {}

  @override
  Future<ResetPasswordResult> resetPassword({
    required String identityCode,
  }) async {
    return ResetPasswordResult(
      id: 'test-id',
      identityCode: identityCode,
      fullName: 'Test Student',
      role: 'student',
      status: 'active',
      mustChangePassword: true,
      temporaryPassword: 'DF@Temporary1',
    );
  }

  @override
  Future<List<AdminRoom>> getActiveRooms() async {
    return [
      AdminRoom(id: 'r1', code: 'A1-101', building: 'Tòa A', isActive: true),
    ];
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

  testWidgets('opens the technician creation dialog for admins', (
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

    await tester.tap(find.byKey(const Key('create-technician-btn')));
    await tester.pumpAndSettle();

    expect(find.byType(CreateTechnicianDialog), findsOneWidget);
  });

  testWidgets('student row opens the edit dialog, but technician rows do not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AccountsRepository(
      accounts: const [
        ManagedAccount(
          fullName: 'Nguyễn An',
          identityCode: 'SV001',
          role: AppRole.student,
          status: AccountStatus.active,
        ),
        ManagedAccount(
          fullName: 'Võ Long',
          identityCode: 'KTV001',
          role: AppRole.technician,
          status: AccountStatus.active,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(repository: repository, isAdmin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-student-SV001')), findsOneWidget);
    expect(find.byKey(const Key('edit-student-KTV001')), findsNothing);
    await tester.tap(find.byKey(const Key('edit-student-SV001')));
    await tester.pumpAndSettle();

    expect(find.byType(EditStudentDialog), findsOneWidget);
    expect(find.text('Mã Sinh viên'), findsOneWidget);
    expect(find.text('Email đăng nhập không thể thay đổi.'), findsOneWidget);
  });

  testWidgets('active student and technician rows expose revoke action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AccountsRepository(
      accounts: const [
        ManagedAccount(
          fullName: 'Nguyễn An',
          identityCode: 'SV001',
          role: AppRole.student,
          status: AccountStatus.active,
        ),
        ManagedAccount(
          fullName: 'Võ Long',
          identityCode: 'KTV001',
          role: AppRole.technician,
          status: AccountStatus.active,
        ),
        ManagedAccount(
          fullName: 'Lê Cường',
          identityCode: 'SV003',
          role: AppRole.student,
          status: AccountStatus.revoked,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(repository: repository, isAdmin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('revoke-account-SV001')), findsOneWidget);
    expect(find.byKey(const Key('revoke-account-KTV001')), findsOneWidget);
    expect(find.byKey(const Key('revoke-account-SV003')), findsNothing);
    await tester.tap(find.byKey(const Key('revoke-account-SV001')));
    await tester.pumpAndSettle();
    expect(find.text('Thu hồi tài khoản?'), findsOneWidget);
    expect(find.text('Vui lòng nhập lý do thu hồi.'), findsNothing);
    await tester.tap(find.text('Thu hồi'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng nhập lý do thu hồi.'), findsOneWidget);
  });

  testWidgets('revoked rows expose restore action and student room selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AccountsRepository(
      accounts: const [
        ManagedAccount(
          fullName: 'Lê Cường',
          identityCode: 'SV003',
          role: AppRole.student,
          status: AccountStatus.revoked,
        ),
        ManagedAccount(
          fullName: 'Bùi Phúc',
          identityCode: 'KTV003',
          role: AppRole.technician,
          status: AccountStatus.revoked,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(repository: repository, isAdmin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('restore-account-SV003')), findsOneWidget);
    expect(find.byKey(const Key('restore-account-KTV003')), findsOneWidget);
    expect(find.byKey(const Key('revoke-account-SV003')), findsNothing);
    await tester.tap(find.byKey(const Key('restore-account-SV003')));
    await tester.pumpAndSettle();

    expect(find.byType(RestoreAccountDialog), findsOneWidget);
    expect(find.text('Phòng đang hoạt động *'), findsOneWidget);
    expect(find.textContaining('Sinh viên tự xác nhận'), findsOneWidget);
  });

  testWidgets('reset password action opens for an account in any status', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _AccountsRepository(
      accounts: const [
        ManagedAccount(
          fullName: 'Nguyễn An',
          identityCode: 'SV001',
          role: AppRole.student,
          status: AccountStatus.active,
        ),
        ManagedAccount(
          fullName: 'Đặng Nam',
          identityCode: 'KTV002',
          role: AppRole.technician,
          status: AccountStatus.locked,
        ),
        ManagedAccount(
          fullName: 'Bùi Phúc',
          identityCode: 'KTV003',
          role: AppRole.technician,
          status: AccountStatus.revoked,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAccountsPage(repository: repository, isAdmin: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reset-password-SV001')), findsOneWidget);
    expect(find.byKey(const Key('reset-password-KTV002')), findsOneWidget);
    expect(find.byKey(const Key('reset-password-KTV003')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset-password-KTV002')));
    await tester.pumpAndSettle();
    expect(find.byType(ResetPasswordDialog), findsOneWidget);
  });

  testWidgets(
    'reset action is available for active, locked and revoked users',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _AccountsRepository(
        accounts: const [
          ManagedAccount(
            fullName: 'Nguyễn An',
            identityCode: 'SV001',
            role: AppRole.student,
            status: AccountStatus.active,
          ),
          ManagedAccount(
            fullName: 'Đặng Nam',
            identityCode: 'KTV002',
            role: AppRole.technician,
            status: AccountStatus.locked,
          ),
          ManagedAccount(
            fullName: 'Bùi Phúc',
            identityCode: 'KTV003',
            role: AppRole.technician,
            status: AccountStatus.revoked,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AdminAccountsPage(repository: repository, isAdmin: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reset-password-SV001')), findsOneWidget);
      expect(find.byKey(const Key('reset-password-KTV002')), findsOneWidget);
      expect(find.byKey(const Key('reset-password-KTV003')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reset-password-KTV002')));
      await tester.pumpAndSettle();
      expect(find.byType(ResetPasswordDialog), findsOneWidget);
    },
  );

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
