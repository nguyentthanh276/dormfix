import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/admin_accounts/data/admin_account_lifecycle_repository.dart';
import 'package:dormfix/features/admin_accounts/data/admin_account_management_repository.dart';
import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/models/account_lifecycle_action.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account.dart';
import 'package:dormfix/features/admin_accounts/models/managed_account_input.dart';
import 'package:dormfix/features/admin_accounts/presentation/admin_account_action_dialog.dart';
import 'package:dormfix/features/admin_accounts/presentation/admin_account_form_page.dart';
import 'package:dormfix/features/admin_rooms/data/admin_room_repository.dart';
import 'package:dormfix/features/admin_rooms/models/admin_room.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

class _Accounts
    implements
        AdminAccountsRepository,
        AdminAccountManagementRepository,
        AdminAccountLifecycleRepository {
  final items = <ManagedAccountDetails>[];
  final creates = <CreateManagedAccount>[];
  final updates = <UpdateManagedAccount>[];
  final transitions =
      <
        ({
          String id,
          AccountStatus expectedStatus,
          AccountLifecycleAction action,
          String? reason,
          String? roomId,
        })
      >[];
  final resets =
      <({String id, AccountStatus expectedStatus, String password})>[];
  Future<void> Function()? beforeCreate;
  Future<void> Function()? beforeTransition;
  Future<void> Function()? beforeReset;
  int listCalls = 0;

  @override
  Future<List<ManagedAccount>> list({
    required String query,
    AppRole? role,
    AccountStatus? status,
    required int offset,
    required int limit,
  }) async {
    listCalls++;
    return items
        .where(
          (item) =>
              item.identityCode.contains(query) &&
              (role == null || item.role == role) &&
              (status == null || item.status == status),
        )
        .skip(offset)
        .take(limit)
        .toList();
  }

  @override
  Future<ManagedAccountDetails> fetchDetails(String identityCode) async =>
      items.singleWhere((item) => item.identityCode == identityCode);

  ManagedAccountDetails savedAccount(CreateManagedAccount input) =>
      ManagedAccountDetails(
        id: 'id-${input.identityCode}',
        fullName: input.fullName,
        identityCode: input.identityCode,
        email: input.email,
        phone: input.phone,
        role: input.role,
        status: AccountStatus.active,
        mustChangePassword: true,
        roomId: input.roomId,
      );

  @override
  Future<ManagedAccountDetails> createAccount(
    CreateManagedAccount input,
  ) async {
    creates.add(input);
    await beforeCreate?.call();
    final details = savedAccount(input);
    items.add(details);
    return details;
  }

  @override
  Future<ManagedAccountDetails> updateAccount(
    UpdateManagedAccount input,
  ) async {
    updates.add(input);
    final index = items.indexWhere((item) => item.id == input.id);
    final original = items[index];
    return items[index] = ManagedAccountDetails(
      id: original.id,
      fullName: input.fullName,
      identityCode: original.identityCode,
      email: original.email,
      phone: input.phone,
      role: original.role,
      status: original.status,
      mustChangePassword: original.mustChangePassword,
      roomId: input.roomId,
    );
  }

  @override
  Future<ManagedAccountDetails> changeAccountStatus({
    required String accountId,
    required AccountStatus expectedStatus,
    required AccountLifecycleAction action,
    String? reason,
    String? roomId,
  }) async {
    transitions.add((
      id: accountId,
      expectedStatus: expectedStatus,
      action: action,
      reason: reason,
      roomId: roomId,
    ));
    await beforeTransition?.call();
    return _replace(accountId, status: action.resultingStatus, roomId: roomId);
  }

  @override
  Future<ManagedAccountDetails> resetTemporaryPassword({
    required String accountId,
    required AccountStatus expectedStatus,
    required String temporaryPassword,
  }) async {
    resets.add((
      id: accountId,
      expectedStatus: expectedStatus,
      password: temporaryPassword,
    ));
    await beforeReset?.call();
    return _replace(accountId, mustChangePassword: true);
  }

  ManagedAccountDetails _replace(
    String id, {
    AccountStatus? status,
    String? roomId,
    bool? mustChangePassword,
  }) {
    final index = items.indexWhere((item) => item.id == id);
    final original = items[index];
    return items[index] = ManagedAccountDetails(
      id: original.id,
      fullName: original.fullName,
      identityCode: original.identityCode,
      email: original.email,
      phone: original.phone,
      role: original.role,
      status: status ?? original.status,
      mustChangePassword: mustChangePassword ?? original.mustChangePassword,
      roomId: roomId ?? original.roomId,
    );
  }
}

Finder _field(String name) => find.byKey(Key('admin-account-$name'));

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String name, String value) async {
  final target = _field(name);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String name) => tester
    .widget<EditableText>(
      find.descendant(of: _field(name), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _openAccounts(WidgetTester tester, _Accounts accounts) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = TechnicianTestAuthRepository()
    ..profile = const UserProfile(
      id: 'admin-id',
      identityCode: 'ADM01',
      fullName: 'Quản trị viên',
      email: 'admin@example.test',
      phone: '0901234567',
      role: AppRole.admin,
      status: 'active',
      room: null,
      mustChangePassword: false,
      canAccess: true,
    );
  await tester.pumpWidget(
    DormFixApp(
      authRepository: auth,
      adminAccountsRepository: accounts,
      adminRoomRepository: MockAdminRoomRepository(
        rooms: [
          AdminRoom(
            id: 'room-active',
            code: 'A101',
            building: 'Tòa A',
            isActive: true,
          ),
          AdminRoom(
            id: 'room-old',
            code: 'A090',
            building: 'Tòa A',
            isActive: false,
          ),
          AdminRoom(
            id: 'room-other',
            code: 'B099',
            building: 'Tòa B',
            isActive: false,
          ),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.dispose();
  });
  await _tap(
    tester,
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Tài khoản'),
    ),
  );
}

Future<void> _fillNewAccount(
  WidgetTester tester,
  String code,
  String password,
) async {
  await _enter(tester, 'identity', code);
  await _enter(tester, 'name', 'Tài khoản $code');
  await _enter(tester, 'email', '$code@example.test');
  await _enter(tester, 'phone', '0901234567');
  await _enter(tester, 'temporary-password', password);
}

Finder _accountMenu(String code) =>
    find.byKey(ValueKey('admin-account-actions-$code'));

Finder _confirmAction() => _field('action-confirm');

Future<void> _openAction(
  WidgetTester tester,
  String code,
  AdminAccountAction action,
) async {
  await _tap(tester, _accountMenu(code));
  await _tap(tester, find.text(action.label));
  expect(find.byType(AdminAccountActionDialog), findsOneWidget);
}

void main() {
  testWidgets(
    '320px student creation selects an active room, validates input, and clears password while saving',
    (tester) async {
      final accounts = _Accounts();
      final pending = Completer<void>();
      accounts.beforeCreate = () => pending.future;
      await _openAccounts(tester, accounts);
      await _tap(tester, find.byKey(const Key('admin-add-account')));
      expect(find.byType(AdminAccountFormPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await _tap(tester, _field('room'));
      expect(find.textContaining('A090'), findsNothing);
      expect(find.textContaining('B099'), findsNothing);
      await _tap(tester, find.text('A101 · Tòa A').last);

      await _tap(tester, _field('save'));
      expect(find.text('Vui lòng nhập mã định danh.'), findsOneWidget);
      expect(accounts.creates, isEmpty);
      const password = '  Temp123  ';
      await _fillNewAccount(tester, 'SV042', password);
      await tester.ensureVisible(_field('save'));
      await tester.tap(_field('save'));
      await tester.pump();
      expect(accounts.creates.single.role, AppRole.student);
      expect(accounts.creates.single.roomId, 'room-active');
      expect(accounts.creates.single.temporaryPassword, password);
      expect(_text(tester, 'temporary-password'), isEmpty);
      expect(tester.widget<FilledButton>(_field('save')).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AdminAccountFormPage), findsOneWidget);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AdminAccountFormPage), findsNothing);
      expect(accounts.listCalls, greaterThan(1));
      expect(find.text('Tài khoản SV042'), findsOneWidget);
      expect(find.textContaining('Đã tạo tài khoản SV042'), findsOneWidget);
      expect(find.textContaining(password), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'technician creation omits room and distinguishes duplicate from unknown write outcome',
    (tester) async {
      final accounts = _Accounts();
      accounts.beforeCreate = () async {
        if (accounts.creates.length == 1) {
          throw const AdminAccountsFailure(
            'Mã định danh hoặc email đã tồn tại.',
          );
        }
        accounts.items.add(accounts.savedAccount(accounts.creates.last));
        throw const AdminAccountsFailure(
          'Chưa xác nhận được kết quả tạo tài khoản.',
          uncertain: true,
        );
      };
      await _openAccounts(tester, accounts);
      await _tap(tester, find.byKey(const Key('admin-add-account')));
      await _tap(tester, _field('role'));
      await _tap(tester, find.text('Kỹ thuật viên').last);
      expect(_field('room'), findsNothing);
      await _fillNewAccount(tester, 'KTV045', 'Temp123');
      await _tap(tester, _field('save'));
      expect(accounts.creates.single.role, AppRole.technician);
      expect(accounts.creates.single.roomId, isNull);
      expect(find.text('Mã định danh hoặc email đã tồn tại.'), findsOneWidget);
      expect(_text(tester, 'identity'), 'KTV045');
      expect(_text(tester, 'temporary-password'), isEmpty);

      await _enter(tester, 'temporary-password', 'Temp456');
      await _tap(tester, _field('save'));
      expect(accounts.creates, hasLength(2));
      expect(
        find.text('Chưa xác nhận được kết quả tạo tài khoản.'),
        findsOneWidget,
      );
      expect(_field('save'), findsNothing);
      expect(_field('temporary-password'), findsNothing);
      await _tap(tester, find.text('Về danh sách để kiểm tra'));
      expect(find.text('Tài khoản KTV045'), findsOneWidget);
      expect(find.textContaining('Đã tạo tài khoản KTV045'), findsNothing);
    },
  );

  testWidgets(
    'student update preserves identity, role and email and saves active room and contact fields',
    (tester) async {
      final accounts = _Accounts()
        ..items.add(
          const ManagedAccountDetails(
            id: 'student-1',
            fullName: 'Tên sinh viên cũ',
            identityCode: 'SV010',
            email: 'existing@example.test',
            phone: '0901000000',
            role: AppRole.student,
            status: AccountStatus.revoked,
            mustChangePassword: false,
            roomId: 'room-old',
          ),
        );
      await _openAccounts(tester, accounts);
      await _tap(
        tester,
        find.byKey(const ValueKey('admin-edit-account-SV010')),
      );
      expect(_text(tester, 'identity'), 'SV010');
      expect(_text(tester, 'email'), 'existing@example.test');
      expect(tester.widget<TextFormField>(_field('identity')).enabled, isFalse);
      expect(tester.widget<TextFormField>(_field('email')).enabled, isFalse);
      expect(_field('role'), findsNothing);
      expect(_field('temporary-password'), findsNothing);
      expect(find.textContaining('A090'), findsOneWidget);
      await _enter(tester, 'name', 'Tên sinh viên đã sửa');
      await _enter(tester, 'phone', '+84901000001');
      await _tap(tester, _field('room'));
      expect(find.textContaining('B099'), findsNothing);
      await _tap(tester, find.text('A101 · Tòa A').last);
      await _tap(tester, _field('save'));
      expect(accounts.updates.single.id, 'student-1');
      expect(accounts.updates.single.fullName, 'Tên sinh viên đã sửa');
      expect(accounts.updates.single.phone, '+84901000001');
      expect(accounts.updates.single.roomId, 'room-active');
      expect(accounts.items.single.identityCode, 'SV010');
      expect(accounts.items.single.email, 'existing@example.test');
      expect(find.text('Tên sinh viên đã sửa'), findsOneWidget);
      expect(find.text('Tên sinh viên cũ'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'KTV lock requires reason and confirmation, reports open jobs, then refreshes for lock and unlock',
    (tester) async {
      const code = 'KTV103';
      final accounts = _Accounts()
        ..items.add(
          const ManagedAccountDetails(
            id: 'technician-103',
            fullName: 'Kỹ thuật viên trực ca',
            identityCode: code,
            email: 'tech103@example.test',
            phone: '0901000000',
            role: AppRole.technician,
            status: AccountStatus.active,
            mustChangePassword: false,
          ),
        );
      accounts.beforeTransition = () async {
        if (accounts.transitions.length == 1) {
          throw const AdminAccountsFailure(
            'Kỹ thuật viên còn công việc chưa hoàn tất.',
            conflict: true,
          );
        }
      };
      await _openAccounts(tester, accounts);
      await _openAction(tester, code, AdminAccountAction.lock);
      await _tap(tester, _confirmAction());
      expect(find.text('Vui lòng nhập lý do.'), findsOneWidget);
      expect(accounts.transitions, isEmpty);
      await _enter(tester, 'action-reason', 'Bàn giao ca');
      await _tap(tester, find.text('Hủy'));
      expect(accounts.transitions, isEmpty);

      await _openAction(tester, code, AdminAccountAction.lock);
      await _enter(tester, 'action-reason', '  Bàn giao ca  ');
      await _tap(tester, _confirmAction());
      expect(accounts.transitions.single.reason, 'Bàn giao ca');
      expect(accounts.transitions.single.expectedStatus, AccountStatus.active);
      expect(accounts.items.single.status, AccountStatus.active);
      expect(
        find.text('Kỹ thuật viên còn công việc chưa hoàn tất.'),
        findsOneWidget,
      );
      expect(_confirmAction(), findsNothing);
      await _tap(tester, find.text('Đóng và tải lại'));
      expect(accounts.listCalls, 2);

      await _openAction(tester, code, AdminAccountAction.lock);
      await _enter(tester, 'action-reason', 'Đã bàn giao ca');
      await _tap(tester, _confirmAction());
      expect(accounts.items.single.status, AccountStatus.locked);
      expect(find.text('Bị khóa'), findsOneWidget);
      await _openAction(tester, code, AdminAccountAction.unlock);
      expect(_field('action-reason'), findsNothing);
      await _tap(tester, _confirmAction());
      expect(accounts.transitions.last.action, AccountLifecycleAction.unlock);
      expect(accounts.transitions.last.expectedStatus, AccountStatus.locked);
      expect(accounts.items.single.status, AccountStatus.active);
      expect(accounts.listCalls, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Student revoke retains the old room; restore requires selecting an active room',
    (tester) async {
      const code = 'SV088';
      final accounts = _Accounts()
        ..items.add(
          const ManagedAccountDetails(
            id: 'student-88',
            fullName: 'Sinh viên chuyển phòng',
            identityCode: code,
            email: 'student88@example.test',
            phone: '0901000000',
            role: AppRole.student,
            status: AccountStatus.active,
            mustChangePassword: false,
            roomId: 'room-old',
          ),
        );
      await _openAccounts(tester, accounts);
      await _openAction(tester, code, AdminAccountAction.revoke);
      await _enter(tester, 'action-reason', 'Rời ký túc xá');
      await _tap(tester, _confirmAction());
      expect(accounts.items.single.status, AccountStatus.revoked);
      expect(accounts.items.single.roomId, 'room-old');

      await _tap(tester, _accountMenu(code));
      expect(find.text(AdminAccountAction.resetPassword.label), findsNothing);
      await _tap(tester, find.text(AdminAccountAction.restore.label));
      await _tap(tester, _confirmAction());
      expect(find.text('Vui lòng chọn phòng.'), findsOneWidget);
      expect(accounts.transitions, hasLength(1));
      await _tap(tester, _field('restore-room'));
      expect(find.textContaining('A090'), findsNothing);
      expect(find.textContaining('B099'), findsNothing);
      await _tap(tester, find.text('A101 · Tòa A').last);
      await _tap(tester, _confirmAction());
      expect(accounts.transitions.last.action, AccountLifecycleAction.restore);
      expect(accounts.transitions.last.roomId, 'room-active');
      expect(accounts.transitions.last.expectedStatus, AccountStatus.revoked);
      expect(accounts.items.single.roomId, 'room-active');
      expect(accounts.items.single.status, AccountStatus.active);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Reset clears the secret on background and submission and asks for refresh after an uncertain result',
    (tester) async {
      const code = 'KTV221';
      const password = '  Temp456  ';
      final pending = Completer<void>();
      final accounts = _Accounts()
        ..items.add(
          const ManagedAccountDetails(
            id: 'technician-221',
            fullName: 'Kỹ thuật viên trực',
            identityCode: code,
            email: 'tech221@example.test',
            phone: '0901000000',
            role: AppRole.technician,
            status: AccountStatus.locked,
            mustChangePassword: false,
          ),
        )
        ..beforeReset = () => pending.future;
      await _openAccounts(tester, accounts);
      await _openAction(tester, code, AdminAccountAction.resetPassword);
      await _enter(tester, 'reset-password', '123');
      await _tap(tester, _confirmAction());
      expect(accounts.resets, isEmpty);
      expect(find.textContaining('ít nhất 6 ký tự'), findsOneWidget);
      await _enter(tester, 'reset-password', password);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_text(tester, 'reset-password'), isEmpty);
      await _enter(tester, 'reset-password', password);

      await tester.tap(_confirmAction());
      await tester.pump();
      expect(accounts.resets.single.password, password);
      expect(accounts.resets.single.expectedStatus, AccountStatus.locked);
      expect(_text(tester, 'reset-password'), isEmpty);
      expect(tester.widget<FilledButton>(_confirmAction()).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AdminAccountActionDialog), findsOneWidget);

      pending.completeError(
        const AdminAccountsFailure(
          'Chưa xác nhận được kết quả đặt lại mật khẩu.',
          uncertain: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa xác nhận được kết quả đặt lại mật khẩu.'),
        findsOneWidget,
      );
      expect(find.textContaining(password), findsNothing);
      expect(_field('reset-password'), findsNothing);
      expect(_confirmAction(), findsNothing);
      await _tap(tester, find.text('Đóng và tải lại'));
      expect(accounts.listCalls, 2);

      accounts.beforeReset = null;
      await _openAction(tester, code, AdminAccountAction.resetPassword);
      await _enter(tester, 'reset-password', password);
      await _tap(tester, _confirmAction());
      expect(accounts.items.single.mustChangePassword, isTrue);
      expect(accounts.items.single.status, AccountStatus.locked);
      expect(
        find.textContaining('Đã đặt lại mật khẩu cho $code'),
        findsOneWidget,
      );
      expect(find.textContaining(password), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
