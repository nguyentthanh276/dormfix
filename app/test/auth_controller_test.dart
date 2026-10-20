import 'dart:async';

import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repositories = <FakeAuthRepository>[];
  setUp(() => repositories.clear());
  tearDown(() async {
    await Future.wait(repositories.map((repository) => repository.dispose()));
  });

  group('AuthController', () {
    for (final role in AppRole.values) {
      test('allows an active ${role.databaseValue} profile', () async {
        final repository = FakeAuthRepository(profile(role: role));
        repositories.add(repository);
        final controller = AuthController(repository: repository);

        await controller.signIn(email: 'user@example.com', password: 'secret');

        expect(controller.state, AuthViewState.authenticated);
        expect(controller.profile?.role, role);
        controller.dispose();
      });
    }

    test('restores a session and clears it after logout', () async {
      final repository = FakeAuthRepository(profile(role: AppRole.student))
        ..hasSession = true;
      repositories.add(repository);
      final controller = AuthController(repository: repository);

      await controller.restoreSession();
      expect(controller.state, AuthViewState.authenticated);

      await controller.signOut();
      expect(controller.state, AuthViewState.signedOut);
      expect(controller.profile, isNull);
      expect(controller.error, isNull);
      expect(repository.hasSession, isFalse);
      controller.dispose();
    });

    test(
      'allows retry instead of granting access after a network failure',
      () async {
        final repository = FakeAuthRepository(profile(role: AppRole.student))
          ..hasSession = true
          ..loadFailure = Exception('private transport detail');
        repositories.add(repository);
        final controller = AuthController(repository: repository);

        await controller.restoreSession();

        expect(controller.state, AuthViewState.retryRequired);
        expect(controller.profile, isNull);
        expect(controller.error, isNot(contains('private transport detail')));
        controller.dispose();
      },
    );

    test('signs out when the profile does not exist', () async {
      final repository = FakeAuthRepository(profile(role: AppRole.student))
        ..hasSession = true
        ..loadFailure = const AuthFailure(
          'Không tìm thấy hồ sơ hợp lệ cho tài khoản này.',
          signOutRequired: true,
        );
      repositories.add(repository);
      final controller = AuthController(repository: repository);

      await controller.restoreSession();

      expect(controller.state, AuthViewState.signedOut);
      expect(repository.hasSession, isFalse);
      expect(repository.signOutCount, 1);
      expect(controller.error, contains('Không tìm thấy hồ sơ'));
      controller.dispose();
    });

    test('denies active profiles without access permission', () async {
      final repository = FakeAuthRepository(
        profile(role: AppRole.student, canAccess: false),
      );
      repositories.add(repository);
      final controller = AuthController(repository: repository);

      await controller.signIn(email: 'user@example.com', password: 'secret');

      expect(controller.state, AuthViewState.signedOut);
      expect(repository.signOutCount, 1);
      expect(controller.error, contains('chưa được cấp quyền'));
      controller.dispose();
    });

    test('keeps the current state and reports logout failures', () async {
      final repository = FakeAuthRepository(profile(role: AppRole.student))
        ..signOutFailure = Exception('private transport detail');
      repositories.add(repository);
      final controller = AuthController(repository: repository);
      await controller.signIn(email: 'user@example.com', password: 'secret');

      await controller.signOut();

      expect(controller.state, AuthViewState.authenticated);
      expect(controller.profile, isNotNull);
      expect(controller.error, contains('Đăng xuất không thành công'));
      expect(controller.error, isNot(contains('private transport detail')));
      controller.dispose();
    });

    for (final status in ['locked', 'revoked']) {
      test('rejects and signs out a $status account', () async {
        final repository = FakeAuthRepository(
          profile(role: null, status: status, canAccess: false),
        );
        repositories.add(repository);
        final controller = AuthController(repository: repository);

        await controller.signIn(email: 'user@example.com', password: 'secret');

        expect(controller.state, AuthViewState.signedOut);
        expect(controller.profile, isNull);
        expect(repository.signOutCount, 1);
        expect(
          controller.error,
          contains(status == 'locked' ? 'khóa' : 'thu hồi'),
        );
        controller.dispose();
      });
    }

    test(
      'locked accounts cannot bypass denial with a password-change flag',
      () async {
        final repository = FakeAuthRepository(
          profile(
            role: null,
            status: 'locked',
            canAccess: false,
            mustChangePassword: true,
          ),
        );
        repositories.add(repository);
        final controller = AuthController(repository: repository);

        await controller.signIn(email: 'user@example.com', password: 'secret');

        expect(controller.state, AuthViewState.signedOut);
        expect(repository.signOutCount, 1);
        expect(controller.error, contains('bị khóa'));
        controller.dispose();
      },
    );

    test('blocks profiles that require a password change', () async {
      final repository = FakeAuthRepository(
        profile(
          role: AppRole.student,
          canAccess: false,
          mustChangePassword: true,
        ),
      );
      repositories.add(repository);
      final controller = AuthController(repository: repository);

      await controller.signIn(email: 'user@example.com', password: 'secret');

      expect(controller.state, AuthViewState.changePasswordRequired);
      expect(controller.profile?.canAccess, isFalse);
      controller.dispose();
    });

    test('locked profile payload does not require or expose role fields', () {
      final locked = UserProfile.fromJson({
        'id': 'profile-id',
        'status': 'locked',
        'can_access': false,
        'must_change_password': false,
      });

      expect(locked.role, isNull);
      expect(locked.status, 'locked');
    });

    test('rejects an active profile with an unknown role', () {
      expect(
        () => UserProfile.fromJson({
          'id': 'profile-id',
          'identity_code': 'DF-001',
          'full_name': 'Người dùng thử',
          'email': 'user@example.com',
          'phone': null,
          'role': 'unknown',
          'status': 'active',
          'room': null,
          'must_change_password': false,
          'can_access': true,
        }),
        throwsFormatException,
      );
    });

    test('surfaces invalid credentials without granting access', () async {
      final repository = FakeAuthRepository(profile(role: AppRole.student))
        ..signInFailure = const AuthFailure(
          'Email hoặc mật khẩu không chính xác.',
        );
      repositories.add(repository);
      final controller = AuthController(repository: repository);

      await controller.signIn(email: 'user@example.com', password: 'wrong');

      expect(controller.state, AuthViewState.signedOut);
      expect(controller.profile, isNull);
      expect(controller.error, contains('không chính xác'));
      controller.dispose();
    });

    test(
      'removes protected content when the session expires externally',
      () async {
        final repository = FakeAuthRepository(profile(role: AppRole.student));
        repositories.add(repository);
        final controller = AuthController(repository: repository);
        await controller.signIn(email: 'user@example.com', password: 'secret');

        repository.hasSession = false;
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, AuthViewState.signedOut);
        expect(controller.profile, isNull);
        expect(controller.error, contains('Phiên đăng nhập đã kết thúc'));
        controller.dispose();
      },
    );
  });

  for (final role in AppRole.values) {
    testWidgets(
      'login routes ${role.databaseValue} to its Home and logout returns to Login',
      (tester) async {
        final repository = FakeAuthRepository(profile(role: role));
        repositories.add(repository);
        await tester.pumpWidget(DormFixApp(authRepository: repository));
        await tester.pumpAndSettle();

        expect(find.text('Đăng nhập DormFix'), findsOneWidget);
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'user@example.com',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'secret');
        await tester.tap(find.text('Đăng nhập'));
        await tester.pumpAndSettle();

        // Sinh viên đã có màn thật (Yêu cầu của tôi); 2 vai trò còn lại vẫn là màn tạm.
        if (role != AppRole.student) {
          expect(find.text('Vai trò: ${role.label}'), findsOneWidget);
        }
        expect(find.text(_homeTitle(role)), findsOneWidget);
        if (role == AppRole.student) {
          // Màn sinh viên tải dữ liệu mock (0,6 giây): chờ xong rồi sang tab Tài khoản.
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(find.byIcon(Icons.person_outline));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Đăng xuất'));
        await tester.pumpAndSettle();

        expect(find.text('Đăng nhập DormFix'), findsOneWidget);
        expect(find.byKey(const Key('auth-error')), findsNothing);
        expect(find.text(_homeTitle(role)), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text(_homeTitle(role)), findsNothing);
      },
    );
  }

  testWidgets('clears login error when typing new credentials', (tester) async {
    final repository = FakeAuthRepository(profile(role: AppRole.student))
      ..signInFailure = const AuthFailure(
        'Email hoặc mật khẩu không chính xác.',
      );
    repositories.add(repository);
    await tester.pumpWidget(DormFixApp(authRepository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-error')), findsOneWidget);
    expect(find.text('Email hoặc mật khẩu không chính xác.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'correct');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-error')), findsNothing);
  });
}

String _homeTitle(AppRole role) => switch (role) {
  AppRole.admin => 'DormFix - Quản lý KTX',
  AppRole.student => 'Yêu cầu của tôi',
  AppRole.technician => 'DormFix - Kỹ thuật viên',
};

UserProfile profile({
  required AppRole? role,
  String status = 'active',
  bool canAccess = true,
  bool mustChangePassword = false,
}) => UserProfile(
  id: 'profile-id',
  identityCode: status == 'active' ? 'DF-001' : null,
  fullName: status == 'active' ? 'Người dùng thử' : null,
  email: status == 'active' ? 'user@example.com' : null,
  phone: null,
  role: role,
  status: status,
  room: null,
  mustChangePassword: mustChangePassword,
  canAccess: canAccess,
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this.profile);

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

  int signOutCount = 0;
  AuthFailure? signInFailure;
  Object? loadFailure;
  Object? signOutFailure;
  Object? changePasswordFailure;
  int changePasswordCount = 0;
  String? lastNewPassword;

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    final failure = signInFailure;
    if (failure != null) throw failure;
    hasSession = true;
    return profile;
  }

  @override
  Future<UserProfile> loadProfile() async {
    final failure = loadFailure;
    if (failure != null) throw failure;
    return profile;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    final failure = signOutFailure;
    if (failure != null) throw failure;
    hasSession = false;
  }

  @override
  Future<UserProfile> changePassword({required String newPassword}) async {
    changePasswordCount++;
    lastNewPassword = newPassword;
    final failure = changePasswordFailure;
    if (failure != null) throw failure;
    return profile.copyWith(mustChangePassword: false, canAccess: true);
  }

  Object? updatePasswordFailure;
  int updatePasswordCount = 0;
  String? lastUpdateCurrentPassword;
  String? lastUpdateNewPassword;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    updatePasswordCount++;
    lastUpdateCurrentPassword = currentPassword;
    lastUpdateNewPassword = newPassword;
    final failure = updatePasswordFailure;
    if (failure != null) throw failure;
  }

  Future<void> dispose() => _sessionController.close();
}
