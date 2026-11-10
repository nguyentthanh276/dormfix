import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/password_rules.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

void main() {
  group('PasswordRules (DF-003 validation)', () {
    test('validateNewPassword checks empty and min length', () {
      expect(
        PasswordRules.validateNewPassword(null),
        'Vui lòng nhập mật khẩu mới.',
      );
      expect(
        PasswordRules.validateNewPassword(''),
        'Vui lòng nhập mật khẩu mới.',
      );
      expect(
        PasswordRules.validateNewPassword('12345'),
        'Mật khẩu mới phải có ít nhất 6 ký tự.',
      );
      expect(PasswordRules.validateNewPassword('123456'), isNull);
      expect(PasswordRules.validateNewPassword('strongPassword123'), isNull);
    });

    test('validateConfirmPassword checks empty and match', () {
      expect(
        PasswordRules.validateConfirmPassword(null, 'secret123'),
        'Vui lòng xác nhận mật khẩu mới.',
      );
      expect(
        PasswordRules.validateConfirmPassword('', 'secret123'),
        'Vui lòng xác nhận mật khẩu mới.',
      );
      expect(
        PasswordRules.validateConfirmPassword('mismatch', 'secret123'),
        'Mật khẩu xác nhận không khớp.',
      );
      expect(
        PasswordRules.validateConfirmPassword('secret123', 'secret123'),
        isNull,
      );
    });

    test('hasMinLength, hasLetter, hasDigit helpers work properly', () {
      expect(PasswordRules.hasMinLength('12345'), isFalse);
      expect(PasswordRules.hasMinLength('123456'), isTrue);
      expect(PasswordRules.hasLetter('123456'), isFalse);
      expect(PasswordRules.hasLetter('12345a'), isTrue);
      expect(PasswordRules.hasDigit('abcdef'), isFalse);
      expect(PasswordRules.hasDigit('abcde1'), isTrue);
    });
  });

  group('AuthController.changeTemporaryPassword', () {
    test(
      'successfully changes password and transitions to authenticated',
      () async {
        final repository = _FakePasswordAuthRepository(
          _testProfile(mustChangePassword: true, canAccess: false),
        );
        final controller = AuthController(repository: repository);
        await controller.signIn(email: 'student@example.com', password: 'temp');
        expect(controller.state, AuthViewState.changePasswordRequired);

        await controller.changeTemporaryPassword(newPassword: 'newSecret123');

        expect(repository.lastNewPassword, 'newSecret123');
        expect(controller.state, AuthViewState.authenticated);
        expect(controller.profile?.mustChangePassword, isFalse);
        expect(controller.profile?.canAccess, isTrue);
        expect(controller.error, isNull);
        controller.dispose();
        await repository.dispose();
      },
    );

    test('keeps changePasswordRequired state on business failure without kicking out', () async {
      final repository =
          _FakePasswordAuthRepository(
              _testProfile(mustChangePassword: true, canAccess: false),
            )
            ..changePasswordFailure = const AuthFailure(
              'Mật khẩu mới không được trùng với mật khẩu cũ.',
            );

      final controller = AuthController(repository: repository);
      await controller.signIn(email: 'student@example.com', password: 'temp');
      expect(controller.state, AuthViewState.changePasswordRequired);

      await controller.changeTemporaryPassword(newPassword: 'temp');

      expect(controller.state, AuthViewState.changePasswordRequired);
      expect(
        controller.error,
        'Mật khẩu mới không được trùng với mật khẩu cũ.',
      );
      expect(controller.profile?.mustChangePassword, isTrue);
      controller.dispose();
      await repository.dispose();
    });

    test('network exception during change password preserves state and shows error', () async {
      final repository = _FakePasswordAuthRepository(
        _testProfile(mustChangePassword: true, canAccess: false),
      )..changePasswordFailure = Exception('Network down');

      final controller = AuthController(repository: repository);
      await controller.signIn(email: 'student@example.com', password: 'temp');
      expect(controller.state, AuthViewState.changePasswordRequired);

      await controller.changeTemporaryPassword(newPassword: 'newSecret123');

      expect(controller.state, AuthViewState.changePasswordRequired);
      expect(
        controller.error,
        contains('Không thể đổi mật khẩu do lỗi kết nối'),
      );
      controller.dispose();
      await repository.dispose();
    });

    test('signs out and surfaces error if account is locked during password change', () async {
      final repository =
          _FakePasswordAuthRepository(
              _testProfile(mustChangePassword: true, canAccess: false),
            )
            ..profileAfterChange = _testProfile(
              status: 'locked',
              mustChangePassword: false,
              canAccess: false,
            );

      final controller = AuthController(repository: repository);
      await controller.signIn(email: 'student@example.com', password: 'temp');
      expect(controller.state, AuthViewState.changePasswordRequired);

      await controller.changeTemporaryPassword(newPassword: 'newSecret123');

      expect(controller.state, AuthViewState.signedOut);
      expect(
        controller.error,
        'Tài khoản đang bị khóa và không được phép truy cập.',
      );
      expect(repository.hasSession, isFalse);

      controller.dispose();
      await repository.dispose();
    });

    test('signs out and surfaces error if account is revoked during password change', () async {
      final repository =
          _FakePasswordAuthRepository(
              _testProfile(mustChangePassword: true, canAccess: false),
            )
            ..profileAfterChange = _testProfile(
              status: 'revoked',
              mustChangePassword: false,
              canAccess: false,
            );

      final controller = AuthController(repository: repository);
      await controller.signIn(email: 'student@example.com', password: 'temp');
      expect(controller.state, AuthViewState.changePasswordRequired);

      await controller.changeTemporaryPassword(newPassword: 'newSecret123');

      expect(controller.state, AuthViewState.signedOut);
      expect(controller.error, 'Quyền truy cập tài khoản đã bị thu hồi.');
      expect(repository.hasSession, isFalse);

      controller.dispose();
      await repository.dispose();
    });
  });

  group('ChangePasswordPage Widget Flow (DF-003)', () {
    testWidgets(
      'shows change password form on login and unlocks student home after success',
      (tester) async {
        final repository = _FakePasswordAuthRepository(
          _testProfile(
            role: AppRole.student,
            mustChangePassword: true,
            canAccess: false,
          ),
        );

        await tester.pumpWidget(DormFixApp(authRepository: repository));
        await tester.pumpAndSettle();

        // Đăng nhập ban đầu
        expect(find.text('Đăng nhập DormFix'), findsOneWidget);
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'student@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'tempPassword',
        );
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        // Phải chuyển sang màn hình đổi mật khẩu tạm
        expect(find.text('Đổi mật khẩu tạm'), findsWidgets);
        expect(find.byKey(const Key('new-password-input')), findsOneWidget);
        expect(find.byKey(const Key('confirm-password-input')), findsOneWidget);
        expect(
          find.byKey(const Key('change-password-submit-btn')),
          findsOneWidget,
        );

        // Thử submit trống -> báo lỗi validation
        await tester.tap(find.byKey(const Key('change-password-submit-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Vui lòng nhập mật khẩu mới.'), findsOneWidget);

        // Nhập mật khẩu quá ngắn
        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          '123',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          '123',
        );
        await tester.tap(find.byKey(const Key('change-password-submit-btn')));
        await tester.pumpAndSettle();
        expect(
          find.text('Mật khẩu mới phải có ít nhất 6 ký tự.'),
          findsOneWidget,
        );

        // Nhập xác nhận không khớp
        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          'newSecret123',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          'differentPass',
        );
        await tester.tap(find.byKey(const Key('change-password-submit-btn')));
        await tester.pumpAndSettle();
        expect(find.text('Mật khẩu xác nhận không khớp.'), findsOneWidget);

        // Nhập đúng và khớp
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          'newSecret123',
        );
        await tester.tap(find.byKey(const Key('change-password-submit-btn')));
        await tester.pumpAndSettle();

        // Đổi mật khẩu thành công: Mở khóa truy cập vào màn hình Yêu cầu của tôi (Sinh viên)
        expect(find.text('Yêu cầu của tôi'), findsOneWidget);
        expect(find.text('Đổi mật khẩu tạm'), findsNothing);

        await repository.dispose();
      },
    );

    testWidgets('allows signing out directly from ChangePasswordPage', (
      tester,
    ) async {
      final repository = _FakePasswordAuthRepository(
        _testProfile(
          role: AppRole.technician,
          mustChangePassword: true,
          canAccess: false,
        ),
      );

      await tester.pumpWidget(DormFixApp(authRepository: repository));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'tech@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'tempPassword');
      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();

      expect(find.text('Đổi mật khẩu tạm'), findsWidgets);

      // Bấm nút Đăng xuất trên AppBar
      await tester.tap(find.widgetWithText(TextButton, 'Đăng xuất'));
      await tester.pumpAndSettle();

      // Quay lại màn hình đăng nhập sạch sẽ
      expect(find.text('Đăng nhập DormFix'), findsOneWidget);
      expect(find.byKey(const Key('auth-error')), findsNothing);

      await repository.dispose();
    });

    testWidgets(
      'shows change password form on login and unlocks technician home after success',
      (tester) async {
        final repository = _FakePasswordAuthRepository(
          _testProfile(
            role: AppRole.technician,
            mustChangePassword: true,
            canAccess: false,
          ),
        );
        final fakeJobsRepo = TechnicianTestJobsRepository();

        await tester.pumpWidget(
          DormFixApp(
            authRepository: repository,
            technicianJobsRepository: fakeJobsRepo,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'tech@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'tempPassword',
        );
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        // Bị chặn tại ChangePasswordPage
        expect(find.text('Đổi mật khẩu tạm'), findsWidgets);
        expect(find.text('Công việc của tôi'), findsNothing);

        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          'newTechPass123',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          'newTechPass123',
        );
        await tester.tap(find.byKey(const Key('change-password-submit-btn')));
        await tester.pumpAndSettle();

        // Mở khóa màn hình Kỹ thuật viên
        expect(find.text('Công việc được giao'), findsOneWidget);
        expect(find.text('Đổi mật khẩu tạm'), findsNothing);

        await repository.dispose();
      },
    );

    testWidgets(
      'toggles visibility independently for new password and confirm password fields',
      (tester) async {
        final repository = _FakePasswordAuthRepository(
          _testProfile(mustChangePassword: true, canAccess: false),
        );

        await tester.pumpWidget(DormFixApp(authRepository: repository));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'user@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'tempPassword',
        );
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        // Ban đầu cả 2 ô đều ẩn (obscureText = true)
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('new-password-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('confirm-password-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );

        // Bấm toggle nút hiện mật khẩu ô 1
        await tester.tap(find.byKey(const Key('new-password-visibility-btn')));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('new-password-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isFalse,
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('confirm-password-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isTrue,
        );

        // Bấm toggle nút hiện mật khẩu ô 2
        await tester.tap(
          find.byKey(const Key('confirm-password-visibility-btn')),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const Key('confirm-password-input')),
                  matching: find.byType(EditableText),
                ),
              )
              .obscureText,
          isFalse,
        );

        await repository.dispose();
      },
    );

    testWidgets(
      'submitting via onFieldSubmitted on confirm password input triggers password change',
      (tester) async {
        final repository = _FakePasswordAuthRepository(
          _testProfile(mustChangePassword: true, canAccess: false),
        );

        await tester.pumpWidget(DormFixApp(authRepository: repository));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'student@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'tempPassword',
        );
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          'newSecret123',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          'newSecret123',
        );
        // Nhấn Done/Enter trên bàn phím (field submitted)
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(repository.lastNewPassword, 'newSecret123');
        expect(find.text('Yêu cầu của tôi'), findsOneWidget);

        await repository.dispose();
      },
    );

    testWidgets(
      'allows signing out directly from bottom logout button on ChangePasswordPage',
      (tester) async {
        final repository = _FakePasswordAuthRepository(
          _testProfile(mustChangePassword: true, canAccess: false),
        );

        await tester.pumpWidget(DormFixApp(authRepository: repository));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'student@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'tempPassword',
        );
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        // Bấm nút Hủy & Đăng xuất dưới form
        await tester.ensureVisible(
          find.byKey(const Key('change-password-bottom-logout-btn')),
        );
        await tester.tap(
          find.byKey(const Key('change-password-bottom-logout-btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Đăng nhập DormFix'), findsOneWidget);

        await repository.dispose();
      },
    );

    testWidgets(
      'clears error when typing in new password or confirm password field',
      (tester) async {
        final repository =
            _FakePasswordAuthRepository(
                _testProfile(mustChangePassword: true, canAccess: false),
              )
              ..changePasswordFailure = const AuthFailure(
                'Mật khẩu không đáp ứng chính sách bảo mật.',
              );

        await tester.pumpWidget(DormFixApp(authRepository: repository));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).at(0),
          'student@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'tempPassword',
        );
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          'newSecret123',
        );
        await tester.enterText(
          find.byKey(const Key('confirm-password-input')),
          'newSecret123',
        );
        await tester.tap(find.byKey(const Key('change-password-submit-btn')));
        await tester.pumpAndSettle();

        expect(
          find.text('Mật khẩu không đáp ứng chính sách bảo mật.'),
          findsOneWidget,
        );

        // Gõ thêm vào ô mật khẩu mới -> Lỗi biến mất
        await tester.enterText(
          find.byKey(const Key('new-password-input')),
          'newSecret1234',
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Mật khẩu không đáp ứng chính sách bảo mật.'),
          findsNothing,
        );

        await repository.dispose();
      },
    );
  });
}

UserProfile _testProfile({
  AppRole role = AppRole.student,
  String status = 'active',
  bool mustChangePassword = false,
  bool canAccess = true,
}) => UserProfile(
  id: 'profile-user-id',
  identityCode: 'SV001',
  fullName: 'Sinh viên Demo',
  email: 'student@example.com',
  phone: '0901234567',
  role: role,
  status: status,
  room: null,
  mustChangePassword: mustChangePassword,
  canAccess: canAccess,
);

class _FakePasswordAuthRepository implements AuthRepository {
  _FakePasswordAuthRepository(this.profile);

  final UserProfile profile;
  final StreamController<bool> _sessionController =
      StreamController<bool>.broadcast(sync: true);
  bool _hasSession = false;

  @override
  bool get hasSession => _hasSession;

  @override
  Stream<bool> get sessionChanges => _sessionController.stream;

  set hasSession(bool value) {
    _hasSession = value;
    _sessionController.add(value);
  }

  String? lastNewPassword;
  Object? changePasswordFailure;
  UserProfile? profileAfterChange;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    hasSession = true;
    return profile;
  }

  @override
  Future<UserProfile> loadProfile() async => profile;

  @override
  Future<void> signOut() async {
    hasSession = false;
  }

  @override
  Future<UserProfile> changePassword({required String newPassword}) async {
    lastNewPassword = newPassword;
    final failure = changePasswordFailure;
    if (failure != null) throw failure;
    return profileAfterChange ??
        profile.copyWith(mustChangePassword: false, canAccess: true);
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  Future<void> dispose() => _sessionController.close();
}
