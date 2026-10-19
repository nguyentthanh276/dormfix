import 'dart:async';

import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/password_rules.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/profile/presentation/active_change_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordRules (DF-004 validation)', () {
    test('validateCurrentPassword checks empty', () {
      expect(
        PasswordRules.validateCurrentPassword(null),
        'Vui lòng nhập mật khẩu hiện tại.',
      );
      expect(
        PasswordRules.validateCurrentPassword(''),
        'Vui lòng nhập mật khẩu hiện tại.',
      );
      expect(PasswordRules.validateCurrentPassword('current123'), isNull);
    });

    test('validateNewPassword rejects duplicate of currentPassword', () {
      expect(
        PasswordRules.validateNewPassword(
          'current123',
          currentPassword: 'current123',
        ),
        'Mật khẩu mới không được trùng với mật khẩu hiện tại.',
      );
      expect(
        PasswordRules.validateNewPassword(
          'newSecret123',
          currentPassword: 'current123',
        ),
        isNull,
      );
    });
  });

  group('AuthController.updatePassword', () {
    test('successfully updates password and remains authenticated', () async {
      final repository = _FakeActivePasswordRepository(_authenticatedProfile());
      final controller = AuthController(repository: repository);
      await controller.restoreSession();
      expect(controller.state, AuthViewState.authenticated);

      final success = await controller.updatePassword(
        currentPassword: 'oldSecret',
        newPassword: 'newSecret123',
      );

      expect(success, isTrue);
      expect(repository.lastCurrentPassword, 'oldSecret');
      expect(repository.lastNewPassword, 'newSecret123');
      expect(controller.state, AuthViewState.authenticated);
      expect(controller.error, isNull);

      controller.dispose();
      await repository.dispose();
    });

    test('wrong current password keeps session and surfaces error', () async {
      final repository = _FakeActivePasswordRepository(_authenticatedProfile())
        ..updateFailure = const AuthFailure(
          'Mật khẩu hiện tại không chính xác.',
        );
      final controller = AuthController(repository: repository);
      await controller.restoreSession();

      final success = await controller.updatePassword(
        currentPassword: 'wrongPassword',
        newPassword: 'newSecret123',
      );

      expect(success, isFalse);
      expect(controller.state, AuthViewState.authenticated);
      expect(controller.error, 'Mật khẩu hiện tại không chính xác.');

      controller.dispose();
      await repository.dispose();
    });

    test(
      'network exception preserves authenticated state and surfaces error',
      () async {
        final repository = _FakeActivePasswordRepository(
          _authenticatedProfile(),
        )..updateFailure = Exception('Network timeout');
        final controller = AuthController(repository: repository);
        await controller.restoreSession();

        final success = await controller.updatePassword(
          currentPassword: 'oldSecret',
          newPassword: 'newSecret123',
        );

        expect(success, isFalse);
        expect(controller.state, AuthViewState.authenticated);
        expect(
          controller.error,
          contains('Không thể đổi mật khẩu do lỗi kết nối'),
        );

        controller.dispose();
        await repository.dispose();
      },
    );

    test('expired session during update signs out user', () async {
      final repository = _FakeActivePasswordRepository(_authenticatedProfile())
        ..updateFailure = const AuthFailure(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          signOutRequired: true,
        );
      final controller = AuthController(repository: repository);
      await controller.restoreSession();

      final success = await controller.updatePassword(
        currentPassword: 'oldSecret',
        newPassword: 'newSecret123',
      );

      expect(success, isFalse);
      expect(controller.state, AuthViewState.signedOut);
      expect(controller.profile, isNull);
      expect(repository.signOutCount, 1);

      controller.dispose();
      await repository.dispose();
    });
  });

  group('ActiveChangePasswordPage Widget Flow (DF-004)', () {
    testWidgets('renders all fields and validates input properly', (
      tester,
    ) async {
      final repository = _FakeActivePasswordRepository(_authenticatedProfile());
      final controller = AuthController(repository: repository);
      await controller.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ActiveChangePasswordPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đổi mật khẩu'), findsWidgets);
      expect(find.byKey(const Key('current-password-input')), findsOneWidget);
      expect(find.byKey(const Key('new-password-input')), findsOneWidget);
      expect(find.byKey(const Key('confirm-password-input')), findsOneWidget);
      expect(
        find.byKey(const Key('active-change-password-submit-btn')),
        findsOneWidget,
      );

      // Submit form trống
      await tester.tap(
        find.byKey(const Key('active-change-password-submit-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vui lòng nhập mật khẩu hiện tại.'), findsOneWidget);
      expect(find.text('Vui lòng nhập mật khẩu mới.'), findsOneWidget);

      // Mật khẩu mới trùng mật khẩu hiện tại
      await tester.enterText(
        find.byKey(const Key('current-password-input')),
        'samePassword123',
      );
      await tester.enterText(
        find.byKey(const Key('new-password-input')),
        'samePassword123',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-input')),
        'samePassword123',
      );
      await tester.tap(
        find.byKey(const Key('active-change-password-submit-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Mật khẩu mới không được trùng với mật khẩu hiện tại.'),
        findsOneWidget,
      );

      // Mật khẩu mới quá ngắn
      await tester.enterText(
        find.byKey(const Key('new-password-input')),
        '123',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-input')),
        '123',
      );
      await tester.tap(
        find.byKey(const Key('active-change-password-submit-btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Mật khẩu mới phải có ít nhất 6 ký tự.'),
        findsOneWidget,
      );

      // Xác nhận không khớp
      await tester.enterText(
        find.byKey(const Key('new-password-input')),
        'newSecret123',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-input')),
        'mismatchPass',
      );
      await tester.tap(
        find.byKey(const Key('active-change-password-submit-btn')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mật khẩu xác nhận không khớp.'), findsOneWidget);

      controller.dispose();
      await repository.dispose();
    });

    testWidgets('successful submit shows SnackBar and clears input fields', (
      tester,
    ) async {
      final repository = _FakeActivePasswordRepository(_authenticatedProfile());
      final controller = AuthController(repository: repository);
      await controller.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ActiveChangePasswordPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('current-password-input')),
        'oldPassword',
      );
      await tester.enterText(
        find.byKey(const Key('new-password-input')),
        'brandNewSecret123',
      );
      await tester.enterText(
        find.byKey(const Key('confirm-password-input')),
        'brandNewSecret123',
      );

      await tester.tap(
        find.byKey(const Key('active-change-password-submit-btn')),
      );
      await tester.pumpAndSettle();

      // Hiện SnackBar thành công
      expect(find.text('Đổi mật khẩu thành công.'), findsOneWidget);

      // Form được reset trống
      final currentField = tester.widget<TextFormField>(
        find.byKey(const Key('current-password-input')),
      );
      final newField = tester.widget<TextFormField>(
        find.byKey(const Key('new-password-input')),
      );
      final confirmField = tester.widget<TextFormField>(
        find.byKey(const Key('confirm-password-input')),
      );

      expect(currentField.controller?.text, isEmpty);
      expect(newField.controller?.text, isEmpty);
      expect(confirmField.controller?.text, isEmpty);

      controller.dispose();
      await repository.dispose();
    });

    testWidgets(
      'surfaces error from wrong current password and clears when typing',
      (tester) async {
        final repository =
            _FakeActivePasswordRepository(_authenticatedProfile())
              ..updateFailure = const AuthFailure(
                'Mật khẩu hiện tại không chính xác.',
              );
        final controller = AuthController(repository: repository);
        await controller.restoreSession();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ActiveChangePasswordPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('current-password-input')),
          'wrongPass',
        );
        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          'validNewPass123',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          'validNewPass123',
        );

        await tester.tap(
          find.byKey(const Key('active-change-password-submit-btn')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth-error')), findsOneWidget);
        expect(find.text('Mật khẩu hiện tại không chính xác.'), findsOneWidget);

        // Gõ lại mật khẩu hiện tại -> lỗi tự động được xóa
        await tester.enterText(
          find.byKey(const Key('current-password-input')),
          'fixingPassword',
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('auth-error')), findsNothing);

        controller.dispose();
        await repository.dispose();
      },
    );
  });
}

UserProfile _authenticatedProfile() => const UserProfile(
  id: 'user-active-123',
  identityCode: 'SV001',
  fullName: 'Sinh viên Nguyễn Văn A',
  email: 'student@example.com',
  phone: '0901234567',
  role: AppRole.student,
  status: 'active',
  room: null,
  mustChangePassword: false,
  canAccess: true,
);

class _FakeActivePasswordRepository implements AuthRepository {
  _FakeActivePasswordRepository(this.profile);

  final UserProfile profile;
  final StreamController<bool> _sessionController =
      StreamController<bool>.broadcast(sync: true);
  bool _hasSession = true;

  @override
  bool get hasSession => _hasSession;

  @override
  Stream<bool> get sessionChanges => _sessionController.stream;

  String? lastCurrentPassword;
  String? lastNewPassword;
  Object? updateFailure;
  int signOutCount = 0;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async => profile;

  @override
  Future<UserProfile> loadProfile() async => profile;

  @override
  Future<void> signOut() async {
    signOutCount++;
    _hasSession = false;
  }

  @override
  Future<UserProfile> changePassword({required String newPassword}) async =>
      profile;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    final failure = updateFailure;
    if (failure != null) throw failure;
  }

  Future<void> dispose() => _sessionController.close();
}
