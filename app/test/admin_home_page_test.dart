import 'dart:async';

import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_requests/data/mock_admin_request_repository.dart';
import 'package:dormfix/features/admin_requests/presentation/admin_home_page.dart';
import 'package:dormfix/features/admin_rooms/presentation/admin_room_list_screen.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/incident_categories/presentation/category_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdminHomePage Dashboard UI & Navigation', () {
    testWidgets(
      'renders modern dashboard with welcome header and 4 feature cards',
      (tester) async {
        final admin = _adminProfile(
          fullName: 'Nguyễn Quản Trị',
          email: 'admin@dormfix.test',
        );
        final authRepo = _FakeAuthRepo(admin);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AdminHomePage(
              controller: authController,
              accountsRepository: const MockAdminAccountsRepository(),
              requestsRepository: const MockAdminRequestRepository(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. AppBar
        expect(find.text('DormFix - Quản lý KTX'), findsOneWidget);
        expect(find.text('Đăng xuất'), findsOneWidget);

        // 2. Welcome Banner
        expect(find.text('Xin chào quản lý, Nguyễn Quản Trị'), findsOneWidget);
        expect(find.text('admin@dormfix.test'), findsOneWidget);
        expect(find.text('Quản trị viên KTX'), findsOneWidget);

        // 3. Section Title
        expect(find.text('Chức năng quản trị'), findsOneWidget);

        // 4. Feature Cards
        expect(find.text('Quản lý yêu cầu sửa chữa'), findsOneWidget);
        expect(
          find.text(
            'Tiếp nhận, điều phối kỹ thuật viên và theo dõi tiến độ xử lý sự cố KTX',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.home_repair_service_outlined), findsOneWidget);

        expect(find.text('Quản lý tài khoản'), findsOneWidget);
        expect(
          find.text(
            'Cấp mới, cập nhật hồ sơ, khóa/thu hồi và đặt lại mật khẩu cho Sinh viên & Kỹ thuật viên',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.manage_accounts_outlined), findsOneWidget);

        expect(find.text('Quản lý phòng ở'), findsOneWidget);
        expect(find.byIcon(Icons.meeting_room_outlined), findsOneWidget);

        expect(find.text('Danh mục sự cố'), findsOneWidget);
        expect(find.byIcon(Icons.category_outlined), findsOneWidget);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets('tapping Quản lý phòng ở navigates to AdminRoomListScreen', (
      tester,
    ) async {
      final admin = _adminProfile();
      final authRepo = _FakeAuthRepo(admin);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminHomePage(
            controller: authController,
            accountsRepository: const MockAdminAccountsRepository(),
            requestsRepository: const MockAdminRequestRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quản lý phòng ở'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminRoomListScreen), findsOneWidget);

      authController.dispose();
      await authRepo.dispose();
    });

    testWidgets('tapping Danh mục sự cố navigates to CategoryListScreen', (
      tester,
    ) async {
      final admin = _adminProfile();
      final authRepo = _FakeAuthRepo(admin);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminHomePage(
            controller: authController,
            accountsRepository: const MockAdminAccountsRepository(),
            requestsRepository: const MockAdminRequestRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Danh mục sự cố'));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryListScreen), findsOneWidget);

      authController.dispose();
      await authRepo.dispose();
    });

    testWidgets('tapping logout button triggers signOut and signs out admin', (
      tester,
    ) async {
      final admin = _adminProfile();
      final authRepo = _FakeAuthRepo(admin);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminHomePage(
            controller: authController,
            accountsRepository: const MockAdminAccountsRepository(),
            requestsRepository: const MockAdminRequestRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Đăng xuất'));
      await tester.pumpAndSettle();

      expect(authRepo.signOutCount, 1);
      expect(authController.state, AuthViewState.signedOut);

      authController.dispose();
      await authRepo.dispose();
    });
  });
}

UserProfile _adminProfile({
  String fullName = 'Admin Master',
  String email = 'admin@example.com',
}) => UserProfile(
  id: 'admin-id-123',
  identityCode: 'ADM001',
  fullName: fullName,
  email: email,
  phone: '0901234567',
  role: AppRole.admin,
  status: 'active',
  room: null,
  mustChangePassword: false,
  canAccess: true,
);

class _FakeAuthRepo implements AuthRepository {
  _FakeAuthRepo(this._profile);

  final UserProfile _profile;
  final StreamController<bool> _changes = StreamController<bool>.broadcast(
    sync: true,
  );
  bool _hasSession = true;
  int signOutCount = 0;

  @override
  bool get hasSession => _hasSession;

  @override
  Stream<bool> get sessionChanges => _changes.stream;

  @override
  Future<UserProfile> loadProfile() async => _profile;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async => _profile;

  @override
  Future<void> signOut() async {
    signOutCount++;
    _hasSession = false;
    _changes.add(false);
  }

  @override
  Future<UserProfile> changePassword({required String newPassword}) async =>
      _profile;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  Future<void> dispose() => _changes.close();
}
