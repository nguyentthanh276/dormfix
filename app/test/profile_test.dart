import 'dart:async';
import 'dart:convert';

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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        expect(PhoneRules.validatePhone('090 123 4567'), isNull);
        expect(PhoneRules.validatePhone('090-123-4567'), isNull);
        expect(PhoneRules.validatePhone('+84 901 234 567'), isNull);
      },
    );

    test(
      'normalize trims and strips dashes, dots and spaces from phone numbers',
      () {
        expect(PhoneRules.normalize(' 090 123 4567 '), '0901234567');
        expect(PhoneRules.normalize('090-123-4567'), '0901234567');
        expect(PhoneRules.normalize('090.123.4567'), '0901234567');
        expect(PhoneRules.normalize(' +84 901-234-567 '), '+84901234567');
        expect(PhoneRules.normalize(null), '');
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

    test('surfaces friendly message when schema cache / RPC function is missing (DF-006, DF-019)', () async {
      final authRepo = _FakeAuthRepo(_studentProfile());
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final profileRepo = _FakeProfileRepo()
        ..failure = const ProfileFailure(
          'Chức năng cập nhật số điện thoại tạm thời chưa khả dụng trên hệ thống. Vui lòng liên hệ quản trị viên để cập nhật cấu hình.',
        );
      final controller = ProfileController(
        authController: authController,
        repository: profileRepo,
      );

      final success = await controller.updatePhone('0909999999');

      expect(success, isFalse);
      expect(
        controller.error,
        'Chức năng cập nhật số điện thoại tạm thời chưa khả dụng trên hệ thống. Vui lòng liên hệ quản trị viên để cập nhật cấu hình.',
      );
      expect(authController.state, AuthViewState.authenticated);

      controller.dispose();
      authController.dispose();
      await authRepo.dispose();
    });

    test('surfaces friendly message when schema cache / RPC function is missing (DF-006, DF-019)', () async {
      final authRepo = _FakeAuthRepo(_studentProfile());
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final profileRepo = _FakeProfileRepo()
        ..failure = const ProfileFailure(
          'Chức năng cập nhật số điện thoại tạm thời chưa khả dụng trên hệ thống. Vui lòng liên hệ quản trị viên để cập nhật cấu hình.',
        );
      final controller = ProfileController(
        authController: authController,
        repository: profileRepo,
      );

      final success = await controller.updatePhone('0909999999');

      expect(success, isFalse);
      expect(
        controller.error,
        'Chức năng cập nhật số điện thoại tạm thời chưa khả dụng trên hệ thống. Vui lòng liên hệ quản trị viên để cập nhật cấu hình.',
      );
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

    test('dirty check: ignores update and does not call repository when phone is unchanged', () async {
      final initialProfile = _studentProfile(phone: '0901111111');
      final authRepo = _FakeAuthRepo(initialProfile);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final profileRepo = _FakeProfileRepo();
      final controller = ProfileController(
        authController: authController,
        repository: profileRepo,
      );

      // Nhập số điện thoại giống hệt hiện tại
      final successSame = await controller.updatePhone('0901111111');
      expect(successSame, isTrue);
      expect(profileRepo.updatePhoneCount, 0);

      // Nhập số điện thoại chứa khoảng trắng/dấu gạch ngang nhưng chuẩn hóa ra giống hệt
      final successFormatted = await controller.updatePhone(' 090-111-1111 ');
      expect(successFormatted, isTrue);
      expect(profileRepo.updatePhoneCount, 0);

      controller.dispose();
      authController.dispose();
      await authRepo.dispose();
    });

    test(
      'normalizes phone number with dashes/spaces before sending to repository',
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

        final success = await controller.updatePhone(' +84 988-776-655 ');
        expect(success, isTrue);
        expect(profileRepo.updatePhoneCount, 1);
        expect(profileRepo.lastPhone, '+84988776655');
        expect(authController.profile?.phone, '+84988776655');

        controller.dispose();
        authController.dispose();
        await authRepo.dispose();
      },
    );

    test('loadProfile fetches latest profile and updates AuthController (Pull-to-Refresh)', () async {
      final initialProfile = _studentProfile(fullName: 'Tên Ban Đầu');
      final authRepo = _FakeAuthRepo(initialProfile);
      final authController = AuthController(repository: authRepo);
      await authController.restoreSession();

      final profileRepo = _FakeProfileRepo()
        ..profileToReturn = _studentProfile(fullName: 'Tên Mới Từ Server');
      final controller = ProfileController(
        authController: authController,
        repository: profileRepo,
      );

      await controller.loadProfile(isRefresh: true);
      expect(profileRepo.getProfileCount, 1);
      expect(authController.profile?.fullName, 'Tên Mới Từ Server');

      controller.dispose();
      authController.dispose();
      await authRepo.dispose();
    });
  });

  group('SupabaseProfileRepository PostgrestException mapping and RPC contract', () {
    final clients = <SupabaseClient>[];

    Future<SupabaseClient> open(
      Future<http.Response> Function(http.Request) handler, {
      String userId = 'student-id-123',
    }) async {
      final client = SupabaseClient(
        'https://dormfix.test',
        'sb_publishable_local_profile_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final response = await handler(request);
          return http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
      );
      clients.add(client);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': _testJwt(userId),
          'token_type': 'bearer',
          'refresh_token': 'local-test-refresh-token',
          'user': {
            'id': userId,
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
            'aud': 'authenticated',
            'created_at': '2026-10-15T00:00:00Z',
          },
        }),
      );
      return client;
    }

    tearDown(() async {
      for (final client in clients) {
        await client.dispose();
      }
      clients.clear();
    });

    test('updatePhone catches PostgREST schema cache PGRST202 error and maps to friendly message', () async {
      final client = await open((request) async {
        expect(request.url.path, '/rest/v1/rpc/update_my_phone');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['p_phone'], '0901234567');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 'PGRST202',
              'details': null,
              'hint': null,
              'message': 'Could not find the function public.update_my_phone(p_phone) in the schema cache',
            }),
          ),
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = SupabaseProfileRepository(client);

      expect(
        () => repo.updatePhone(phone: '0901234567'),
        throwsA(
          isA<ProfileFailure>().having(
            (f) => f.message,
            'message',
            'Chức năng cập nhật số điện thoại tạm thời chưa khả dụng trên hệ thống. Vui lòng liên hệ quản trị viên để cập nhật cấu hình.',
          ),
        ),
      );
    });

    test(
      'updatePhone successfully calls RPC with p_phone and returns UserProfile',
      () async {
        final client = await open((request) async {
          expect(request.url.path, '/rest/v1/rpc/update_my_phone');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['p_phone'], '0901234567');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 'student-id-123',
                'identity_code': 'SV001',
                'full_name': 'Sinh viên Test',
                'email': 'student@test.local',
                'phone': '0901234567',
                'role': 'student',
                'status': 'active',
                'room': null,
                'must_change_password': false,
                'can_access': true,
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final repo = SupabaseProfileRepository(client);
        final profile = await repo.updatePhone(phone: '0901234567');

        expect(profile.phone, '0901234567');
        expect(profile.fullName, 'Sinh viên Test');
      },
    );

    test(
      'getProfile catches schema cache PGRST202 and maps to friendly message',
      () async {
        final client = await open((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_my_profile');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 'PGRST202',
                'details': null,
                'hint': null,
                'message': 'Could not find the function public.get_my_profile() in the schema cache',
              }),
            ),
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final repo = SupabaseProfileRepository(client);

        expect(
          () => repo.getProfile(),
          throwsA(
            isA<ProfileFailure>().having(
              (f) => f.message,
              'message',
              'Dịch vụ thông tin hồ sơ tạm thời chưa khả dụng. Vui lòng liên hệ quản trị viên.',
            ),
          ),
        );
      },
    );
  });

  group('SupabaseProfileRepository PostgrestException mapping and RPC contract', () {
    final clients = <SupabaseClient>[];

    Future<SupabaseClient> open(
      Future<http.Response> Function(http.Request) handler, {
      String userId = 'student-id-123',
    }) async {
      final client = SupabaseClient(
        'https://dormfix.test',
        'sb_publishable_local_profile_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final response = await handler(request);
          return http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
      );
      clients.add(client);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': _testJwt(userId),
          'token_type': 'bearer',
          'refresh_token': 'local-test-refresh-token',
          'user': {
            'id': userId,
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
            'aud': 'authenticated',
            'created_at': '2026-10-15T00:00:00Z',
          },
        }),
      );
      return client;
    }

    tearDown(() async {
      for (final client in clients) {
        await client.dispose();
      }
      clients.clear();
    });

    test('updatePhone catches PostgREST schema cache PGRST202 error and maps to friendly message', () async {
      final client = await open((request) async {
        expect(request.url.path, '/rest/v1/rpc/update_my_phone');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['p_phone'], '0901234567');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'code': 'PGRST202',
              'details': null,
              'hint': null,
              'message': 'Could not find the function public.update_my_phone(p_phone) in the schema cache',
            }),
          ),
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = SupabaseProfileRepository(client);

      expect(
        () => repo.updatePhone(phone: '0901234567'),
        throwsA(
          isA<ProfileFailure>().having(
            (f) => f.message,
            'message',
            'Chức năng cập nhật số điện thoại tạm thời chưa khả dụng trên hệ thống. Vui lòng liên hệ quản trị viên để cập nhật cấu hình.',
          ),
        ),
      );
    });

    test(
      'updatePhone successfully calls RPC with p_phone and returns UserProfile',
      () async {
        final client = await open((request) async {
          expect(request.url.path, '/rest/v1/rpc/update_my_phone');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['p_phone'], '0901234567');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'id': 'student-id-123',
                'identity_code': 'SV001',
                'full_name': 'Sinh viên Test',
                'email': 'student@test.local',
                'phone': '0901234567',
                'role': 'student',
                'status': 'active',
                'room': null,
                'must_change_password': false,
                'can_access': true,
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final repo = SupabaseProfileRepository(client);
        final profile = await repo.updatePhone(phone: '0901234567');

        expect(profile.phone, '0901234567');
        expect(profile.fullName, 'Sinh viên Test');
      },
    );

    test(
      'getProfile catches schema cache PGRST202 and maps to friendly message',
      () async {
        final client = await open((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_my_profile');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 'PGRST202',
                'details': null,
                'hint': null,
                'message': 'Could not find the function public.get_my_profile() in the schema cache',
              }),
            ),
            404,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        final repo = SupabaseProfileRepository(client);

        expect(
          () => repo.getProfile(),
          throwsA(
            isA<ProfileFailure>().having(
              (f) => f.message,
              'message',
              'Dịch vụ thông tin hồ sơ tạm thời chưa khả dụng. Vui lòng liên hệ quản trị viên.',
            ),
          ),
        );
      },
    );
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
      expect(find.byKey(const Key('dormfix-account-menu')), findsOneWidget);
      await tester.tap(find.byKey(const Key('dormfix-account-menu')));
      await tester.pumpAndSettle();

      // Đã mở ProfilePage
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Kỹ thuật viên Test'), findsOneWidget);

      authController.dispose();
      await authRepo.dispose();
    });

    testWidgets(
      'dirty check on ProfilePage: shows SnackBar and skips updatePhone when phone is unchanged',
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

        // Nhập số điện thoại giống hệt hiện tại
        await tester.enterText(
          find.byKey(const Key('profile-phone-input')),
          '0901111111',
        );
        await tester.ensureVisible(
          find.byKey(const Key('profile-save-phone-btn')),
        );
        await tester.tap(find.byKey(const Key('profile-save-phone-btn')));
        await tester.pumpAndSettle();

        expect(find.text('Số điện thoại không thay đổi.'), findsOneWidget);
        expect(profileRepo.updatePhoneCount, 0);

        // Nhập số điện thoại có khoảng trắng/gạch ngang nhưng chuẩn hóa ra giống hệt
        await tester.enterText(
          find.byKey(const Key('profile-phone-input')),
          ' 090-111-1111 ',
        );
        await tester.tap(find.byKey(const Key('profile-save-phone-btn')));
        await tester.pumpAndSettle();

        expect(find.text('Số điện thoại không thay đổi.'), findsOneWidget);
        expect(profileRepo.updatePhoneCount, 0);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets(
      'pull-to-refresh on ProfilePage triggers loadProfile and updates screen',
      (tester) async {
        final initialStudent = _studentProfile(fullName: 'Sinh viên Cũ');
        final authRepo = _FakeAuthRepo(initialStudent);
        final authController = AuthController(repository: authRepo);
        await authController.restoreSession();

        final profileRepo = _FakeProfileRepo()
          ..profileToReturn = _studentProfile(
            fullName: 'Sinh viên Đã Cập Nhật',
          );

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

        expect(find.text('Sinh viên Cũ'), findsOneWidget);

        // Kéo RefreshIndicator xuống
        await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
        await tester.pumpAndSettle();

        expect(profileRepo.getProfileCount, greaterThan(0));
        expect(find.text('Sinh viên Đã Cập Nhật'), findsOneWidget);

        authController.dispose();
        await authRepo.dispose();
      },
    );

    testWidgets(
      'renders lock outline icons for read-only fields on ProfilePage (DF-005)',
      (tester) async {
        final student = _studentProfile(
          fullName: 'Sinh viên An',
          identityCode: 'SV123',
          email: 'an@dorm.test',
          roomCode: 'A101',
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

        // Biểu tượng khóa (Icons.lock_outline) xuất hiện cho các trường Read-only
        expect(find.byIcon(Icons.lock_outline), findsWidgets);

        authController.dispose();
        await authRepo.dispose();
      },
    );
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
  int getProfileCount = 0;
  ProfileFailure? failure;
  UserProfile? profileToReturn;

  @override
  Future<UserProfile> getProfile() async {
    getProfileCount++;
    final f = failure;
    if (f != null) throw f;
    return profileToReturn ?? _studentProfile();
  }

  @override
  Future<UserProfile> updatePhone({required String phone}) async {
    updatePhoneCount++;
    lastPhone = phone;
    final f = failure;
    if (f != null) throw f;
    return _studentProfile(phone: phone);
  }
}

String _testJwt(String userId) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiresAt =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': userId, 'role': 'authenticated', 'exp': expiresAt})}.'
      'local-test-signature';
}
