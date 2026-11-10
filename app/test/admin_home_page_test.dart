import 'dart:async';

import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/core/widgets/dormfix_app_bar.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_requests/data/mock_admin_request_repository.dart';
import 'package:dormfix/features/admin_requests/presentation/admin_home_page.dart';
import 'package:dormfix/features/admin_requests/presentation/admin_request_detail_page.dart';
import 'package:dormfix/features/admin_rooms/presentation/admin_room_list_screen.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/incident_categories/presentation/category_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<(_FakeAuthRepo, AuthController)> pumpHome(WidgetTester tester) async {
    final repository = _FakeAuthRepo(_adminProfile());
    final controller = AuthController(repository: repository);
    await controller.restoreSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminHomePage(
          controller: controller,
          accountsRepository: const MockAdminAccountsRepository(),
          requestsRepository: const MockAdminRequestRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await repository.dispose();
    });
    return (repository, controller);
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts at requests and uses one shared header and four tabs', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(find.byType(DormFixAppBar), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('DormFix · Admin'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('DF000101'), findsOneWidget);
    expect(find.text('Đăng xuất'), findsNothing);
    expect(find.text('Chức năng quản trị'), findsNothing);
    expect(find.byType(AdminRoomListScreen), findsNothing);
    expect(find.byType(CategoryListScreen), findsNothing);
  });

  testWidgets(
    'tabs retain account search and do not create duplicate headers',
    (tester) async {
      await pumpHome(tester);
      await selectTab(tester, 'Tài khoản');
      await tester.enterText(find.byType(TextField), 'Nguyễn');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await selectTab(tester, 'Phòng');
      expect(find.byType(AdminRoomListScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      await selectTab(tester, 'Loại sự cố');
      expect(find.byType(CategoryListScreen), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      await selectTab(tester, 'Tài khoản');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Nguyễn',
      );
      expect(find.byType(DataTable), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
    },
  );

  testWidgets('detail hides bottom tabs and Back restores request scroll', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);
    final list = find.byKey(const PageStorageKey('admin-requests-list'));
    await tester.scrollUntilVisible(
      find.text('DF000105'),
      250,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    await tester.tap(find.text('DF000105'));
    await tester.pumpAndSettle();
    expect(find.byType(AdminRequestDetailPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    final after = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;
    expect(after, closeTo(before, 1));
    expect(find.text('DF000105'), findsOneWidget);
  });

  testWidgets('account menu shows identity and signs out', (tester) async {
    final (repository, controller) = await pumpHome(tester);
    await tester.tap(find.byKey(const Key('dormfix-account-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Admin Master'), findsOneWidget);
    expect(find.text('admin@example.com'), findsOneWidget);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(repository.signOutCount, 1);
    expect(controller.state, AuthViewState.signedOut);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('expired session removes nested detail and its open dialog', (
    tester,
  ) async {
    final (repository, _) = await pumpHome(tester);
    await tester.tap(find.text('DF000101'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Phân công Kỹ thuật viên'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Phân công Kỹ thuật viên'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    repository.expire();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(AdminRequestDetailPage), findsNothing);
    expect(find.text('DF000101'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('all Admin tabs and expanded filters fit a 320px phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Bộ lọc'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final label in ['Tài khoản', 'Phòng', 'Loại sự cố', 'Yêu cầu']) {
      await selectTab(tester, label);
      expect(tester.takeException(), isNull, reason: label);
    }
  });
}

UserProfile _adminProfile() => const UserProfile(
  id: 'admin-id-123',
  identityCode: 'ADM001',
  fullName: 'Admin Master',
  email: 'admin@example.com',
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
  final _changes = StreamController<bool>.broadcast(sync: true);
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
  void expire() {
    _hasSession = false;
    _changes.add(false);
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    expire();
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
