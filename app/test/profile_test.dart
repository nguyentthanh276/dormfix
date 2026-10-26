import 'dart:async';

import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/profile/data/profile_repository.dart';
import 'package:dormfix/features/profile/models/phone_rules.dart';
import 'package:dormfix/features/profile/presentation/active_change_password_page.dart';
import 'package:dormfix/features/profile/presentation/profile_controller.dart';
import 'package:dormfix/features/profile/presentation/profile_page.dart';
import 'package:dormfix/features/technician_jobs/presentation/technician_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

void main() {
  group('PhoneRules (DF-006 & DF-019 validation)', () {
    test('validatePhone checks null, empty and whitespace', () {
      expect(PhoneRules.validatePhone(null), 'Vui lòng nhập số điện thoại.');
      expect(PhoneRules.validatePhone(''), 'Vui lòng nhập số điện thoại.');
      expect(PhoneRules.validatePhone('   '), 'Vui lòng nhập số điện thoại.');
    });

    test('validatePhone rejects invalid phone format', () {
      expect(PhoneRules.validatePhone('12345'), 'Số điện thoại không hợp lệ.');
      expect(
        PhoneRules.validatePhone('090123456'),
        'Số điện thoại không hợp lệ.',
      );
      expect(
        PhoneRules.validatePhone('09012345678'),
        'Số điện thoại không hợp lệ.',
      );
      expect(
        PhoneRules.validatePhone('090123456a'),
        'Số điện thoại không hợp lệ.',
      );
      expect(
        PhoneRules.validatePhone('+8490123456'),
        'Số điện thoại không hợp lệ.',
      );
      expect(
        PhoneRules.validatePhone('+849012345678'),
        'Số điện thoại không hợp lệ.',
      );
    });

    test(
      'validatePhone accepts valid 10-digit VN phone numbers and +84 format',
      () {
        expect(PhoneRules.validatePhone('0901234567'), isNull);
        expect(PhoneRules.validatePhone('0398765432'), isNull);
        expect(PhoneRules.validatePhone('0000000001'), isNull);
        expect(PhoneRules.validatePhone('+84901234567'), isNull);
        expect(PhoneRules.validatePhone('  0901234567  '), isNull);
      },
    );
  });

  group('ProfileController', () {
    test(
      'validates phone and stops before calling repository on format error',
      () async {
        final authRepo = _FakeAuthRepo(_studentProfile());
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        final profileRepo = _FakeProfileRepo();
        final controller = ProfileController(
          authController: authController,
          repository: profileRepo,
        );

        final success = await controller.updatePhone('invalid_phone');

        expect(success, isFalse);
        expect(controller.error, 'Số điện thoại không hợp lệ.');
        expect(profileRepo.updatePhoneCount, 0);

        controller.clearError();
        expect(controller.error, isNull);

        controller.dispose();
        authController.dispose();
        await authRepo.dispose();
      },
    );

    test(
      'successfully updates phone and synchronizes profile in AuthController',
      () async {
        final initialProfile = _studentProfile(phone: '0901111111');
        final authRepo = _FakeAuthRepo(initialProfile);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        final profileRepo = _FakeProfileRepo();
        final controller = ProfileController(
          authController: authController,
          repository: profileRepo,
        );

        final success = await controller.updatePhone('0909999999');

        expect(success, isTrue);
        expect(controller.error, isNull);
        expect(profileRepo.updatePhoneCount, 1);
        expect(profileRepo.lastPhone, '0909999999');
        expect(authController.profile?.phone, '0909999999');

        controller.dispose();
        authController.dispose();
        await authRepo.dispose();
      },
    );

    test('handles ProfileFailure and surfaces friendly message', () async {
      final authRepo = _FakeAuthRepo(_studentProfile());
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final profileRepo = _FakeProfileRepo()
        ..failure = const ProfileFailure(
          'Không thể cập nhật số điện thoại lúc này.',
        );
      final controller = ProfileController(
        authController: authController,
        repository: profileRepo,
      );

      final success = await controller.updatePhone('0909999999');

      expect(success, isFalse);
      expect(controller.error, 'Không thể cập nhật số điện thoại lúc này.');
      expect(authController.state, AuthViewState.authenticated);

      controller.dispose();
      authController.dispose();
      await authRepo.dispose();
    });

    test('signs out user if ProfileFailure requires sign out', () async {
      final authRepo = _FakeAuthRepo(_studentProfile());
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final profileRepo = _FakeProfileRepo()
        ..failure = const ProfileFailure(
          'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
          signOutRequired: true,
        );
      final controller = ProfileController(
        authController: authController,
        repository: profileRepo,
      );

      final success = await controller.updatePhone('0909999999');

      expect(success, isFalse);
      expect(authController.state, AuthViewState.signedOut);
      expect(authRepo.signOutCount, 1);

      controller.dispose();
      authController.dispose();
      await authRepo.dispose();
    });
  });

  group('ProfilePage Widget Flow', () {
    testWidgets(
      'DF-005 Student Profile renders all read-only fields and room info',
      (tester) async {
        final student = _studentProfile(
          fullName: 'Sinh viên Nguyễn An',
          identityCode: 'SV12345',
          email: 'an.nguyen@dorm.test',
          phone: '0901234567',
          roomCode: 'DEMO-A101',
        );
        final authRepo = _FakeAuthRepo(student);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ProfilePage(controller: authController),
          ),
        );
        await tester.pumpAndSettle();

        // Tiêu đề trang
        expect(find.text('Hồ sơ cá nhân'), findsOneWidget);

        // Thông tin hiển thị
        expect(find.text('Sinh viên Nguyễn An'), findsOneWidget);
        expect(find.text('Sinh viên'), findsOneWidget);
        expect(find.text('Mã sinh viên'), findsOneWidget);
        expect(find.text('SV12345'), findsOneWidget);
        expect(find.text('Email'), findsOneWidget);
        expect(find.text('an.nguyen@dorm.test'), findsOneWidget);
        expect(find.text('Phòng'), findsOneWidget);
        expect(find.text('DEMO-A101'), findsOneWidget);
        expect(find.text('0901234567'), findsWidgets);

        // Các trường Email, Họ tên, Mã SV, Phòng ở hoàn toàn Read-only (không có TextFormField cho chúng)
        // Chỉ có DUY NHẤT 1 TextFormField trên toàn màn hình (dành cho Số điện thoại mới)
        expect(find.byType(TextFormField), findsOneWidget);
        expect(find.byKey(const Key('profile-phone-input')), findsOneWidget);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets('DF-018 Technician Profile renders info without room section', (
      tester,
    ) async {
      final tech = _technicianProfile(
        fullName: 'Kỹ thuật viên Trần Bình',
        identityCode: 'KTV999',
        email: 'binh.tran@dorm.test',
        phone: '0912345678',
      );
      final authRepo = _FakeAuthRepo(tech);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ProfilePage(controller: authController),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kỹ thuật viên Trần Bình'), findsOneWidget);
      expect(find.text('Kỹ thuật viên'), findsOneWidget);
      expect(find.text('Mã kỹ thuật viên'), findsOneWidget);
      expect(find.text('KTV999'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('binh.tran@dorm.test'), findsOneWidget);
      expect(find.text('0912345678'), findsWidgets);

      // Kỹ thuật viên không có thông tin phòng ở
      expect(find.text('Phòng'), findsNothing);

      authController.dispose();
      await authRepo.dispose();
    });

    testWidgets(
      'DF-006 & DF-019 Update Phone validates, submits, updates profile and displays SnackBar',
      (tester) async {
        final initialStudent = _studentProfile(phone: '0901111111');
        final authRepo = _FakeAuthRepo(initialStudent);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        final profileRepo = _FakeProfileRepo();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ProfilePage(
              controller: authController,
              profileRepository: profileRepo,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Nhập chuỗi rỗng -> Báo lỗi bắt buộc nhập
        await tester.enterText(
          find.byKey(const Key('profile-phone-input')),
          '',
        );
        await tester.ensureVisible(
          find.byKey(const Key('profile-save-phone-btn')),
        );
        await tester.tap(find.byKey(const Key('profile-save-phone-btn')));
        await tester.pumpAndSettle();

        expect(find.text('Vui lòng nhập số điện thoại.'), findsOneWidget);
        expect(profileRepo.updatePhoneCount, 0);

        // Nhập định dạng sai -> Báo lỗi định dạng
        await tester.enterText(
          find.byKey(const Key('profile-phone-input')),
          '123456',
        );
        await tester.ensureVisible(
          find.byKey(const Key('profile-save-phone-btn')),
        );
        await tester.tap(find.byKey(const Key('profile-save-phone-btn')));
        await tester.pumpAndSettle();

        expect(find.text('Số điện thoại không hợp lệ.'), findsOneWidget);
        expect(profileRepo.updatePhoneCount, 0);

        // Nhập số điện thoại hợp lệ -> Cập nhật thành công
        await tester.enterText(
          find.byKey(const Key('profile-phone-input')),
          '0988776655',
        );
        await tester.ensureVisible(
          find.byKey(const Key('profile-save-phone-btn')),
        );
        await tester.tap(find.byKey(const Key('profile-save-phone-btn')));
        await tester.pumpAndSettle();

        expect(find.text('Cập nhật số điện thoại thành công.'), findsOneWidget);
        expect(profileRepo.updatePhoneCount, 1);
        expect(profileRepo.lastPhone, '0988776655');

        // Hồ sơ được cập nhật cục bộ và hiển thị số điện thoại mới
        expect(find.text('0988776655'), findsWidgets);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets(
      'Tapping change password button navigates to ActiveChangePasswordPage',
      (tester) async {
        final student = _studentProfile();
        final authRepo = _FakeAuthRepo(student);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ProfilePage(controller: authController),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile-change-password-btn')));
        await tester.pumpAndSettle();

        // Đã mở màn hình ActiveChangePasswordPage (DF-004)
        expect(find.byType(ActiveChangePasswordPage), findsOneWidget);
        expect(find.byKey(const Key('current-password-input')), findsOneWidget);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets(
      'Tapping logout button invokes onSignOut / controller.signOut',
      (tester) async {
        final student = _studentProfile();
        final authRepo = _FakeAuthRepo(student);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        var customSignOutCalled = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ProfilePage(
              controller: authController,
              onSignOut: () => customSignOutCalled++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('profile-logout-btn')));
        await tester.pumpAndSettle();

        expect(customSignOutCalled, 1);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets('TechnicianHomePage profile button opens ProfilePage', (
      tester,
    ) async {
      final tech = _technicianProfile();
      final authRepo = _FakeAuthRepo(tech);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final fakeJobsRepo = TechnicianTestJobsRepository();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TechnicianHomePage(
            controller: authController,
            repository: fakeJobsRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nút profile trên AppBar
      expect(find.byKey(const Key('technician-profile-btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('technician-profile-btn')));
      await tester.pumpAndSettle();

      // Đã mở ProfilePage
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Kỹ thuật viên Test'), findsOneWidget);

      authController.dispose();
      await authRepo.dispose();
    });
  });
}

UserProfile _studentProfile({
  String fullName = 'Sinh viên Demo',
  String identityCode = 'SV001',
  String email = 'student@example.com',
  String? phone = '0901234567',
  String? roomCode = 'DEMO-A101',
}) => UserProfile(
  id: 'student-id-123',
  identityCode: identityCode,
  fullName: fullName,
  email: email,
  phone: phone,
  role: AppRole.student,
  status: 'active',
  room: roomCode != null
      ? RoomProfile(
          id: 'room-1',
          code: roomCode,
          building: null,
          isActive: true,
        )
      : null,
  mustChangePassword: false,
  canAccess: true,
);

UserProfile _technicianProfile({
  String fullName = 'Kỹ thuật viên Test',
  String identityCode = 'KTV001',
  String email = 'tech@example.com',
  String? phone = '0902222222',
}) => UserProfile(
  id: 'tech-id-123',
  identityCode: identityCode,
  fullName: fullName,
  email: email,
  phone: phone,
  role: AppRole.technician,
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

class _FakeProfileRepo implements ProfileRepository {
  String? lastPhone;
  int updatePhoneCount = 0;
  ProfileFailure? failure;

  @override
  Future<UserProfile> getProfile() async => _studentProfile();

  @override
  Future<UserProfile> updatePhone({required String phone}) async {
    updatePhoneCount++;
    lastPhone = phone;
    final f = failure;
    if (f != null) throw f;
    return _studentProfile(phone: phone);
  }
}
