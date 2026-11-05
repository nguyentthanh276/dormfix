import 'package:dormfix/app/startup_page.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/presentation/admin_accounts_page.dart';
import 'package:dormfix/features/admin_accounts/presentation/create_student_dialog.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/auth/presentation/change_password_page.dart';
import 'package:dormfix/features/profile/models/phone_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._profile);

  UserProfile? _profile;

  @override
  bool get hasSession => _profile != null;

  @override
  Stream<bool> get sessionChanges => Stream.value(_profile != null);

  @override
  Future<UserProfile> loadProfile() async {
    if (_profile == null) throw const AuthFailure('No session');
    return _profile!;
  }

  @override
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    return loadProfile();
  }

  @override
  Future<void> signOut() async {
    _profile = null;
  }

  @override
  Future<UserProfile> changePassword({required String newPassword}) async {
    _profile = _profile?.copyWith(mustChangePassword: false, canAccess: true);
    return _profile!;
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
}

void main() {
  group('DF-031: MockAdminAccountsRepository Business Logic', () {
    late MockAdminAccountsRepository repository;

    setUp(() {
      repository = const MockAdminAccountsRepository();
    });

    test('Tạo tài khoản Sinh viên hợp lệ với phòng đang hoạt động', () async {
      final result = await repository.createStudent(
        identityCode: 'SV88001',
        fullName: 'Nguyễn Văn Nam',
        email: 'nam.nv88@example.com',
        phone: '0912345678',
        roomId: 'room-1',
      );

      expect(result.identityCode, 'SV88001');
      expect(result.fullName, 'Nguyễn Văn Nam');
      expect(result.email, 'nam.nv88@example.com');
      expect(result.phone, '0912345678');
      expect(result.role, 'student');
      expect(result.status, 'active');
      expect(result.mustChangePassword, isTrue);
      expect(result.temporaryPassword.isNotEmpty, isTrue);
      expect(result.roomCode, 'DEMO-A101');
      expect(result.roomBuilding, 'Tòa A');

      // Tài khoản vừa tạo phải xuất hiện trong danh sách tài khoản
      final list = await repository.list(
        query: 'SV88001',
        offset: 0,
        limit: 10,
      );
      expect(list.any((a) => a.identityCode == 'SV88001'), isTrue);
    });

    test('Chấp nhận số điện thoại định dạng quốc tế +84', () async {
      final result = await repository.createStudent(
        identityCode: 'SV88002',
        fullName: 'Lê Hoàng Yến',
        email: 'yen.lh@example.com',
        phone: '+84987654321',
        roomId: 'room-2',
      );
      expect(result.phone, '+84987654321');
    });

    test('Từ chối khi trùng mã Sinh viên (kể cả chữ hoa/thường)', () async {
      expect(
        () => repository.createStudent(
          identityCode: 'sv001', // Đã có SV001 trong hệ thống
          fullName: 'Người Trùng Mã',
          email: 'khac1@example.com',
          phone: '0912345678',
          roomId: 'room-1',
        ),
        throwsA(
          isA<AdminAccountsFailure>().having(
            (e) => e.message,
            'message',
            contains('Mã Sinh viên đã tồn tại trên hệ thống.'),
          ),
        ),
      );
    });

    test('Từ chối khi trùng email (kể cả chữ hoa/thường)', () async {
      expect(
        () => repository.createStudent(
          identityCode: 'SV88003',
          fullName: 'Người Trùng Email',
          email: 'SV001@EXAMPLE.COM', // Đã có sv001@example.com
          phone: '0912345678',
          roomId: 'room-1',
        ),
        throwsA(
          isA<AdminAccountsFailure>().having(
            (e) => e.message,
            'message',
            contains('Email đã tồn tại trên hệ thống.'),
          ),
        ),
      );
    });

    test(
      'Tài khoản đã thu hồi (revoked) KHÔNG được tái sử dụng mã Sinh viên',
      () async {
        // SV003 là tài khoản đã thu hồi (status: revoked)
        expect(
          () => repository.createStudent(
            identityCode: 'SV003',
            fullName: 'Tái sinh SV003',
            email: 'newemail@example.com',
            phone: '0912345678',
            roomId: 'room-1',
          ),
          throwsA(
            isA<AdminAccountsFailure>().having(
              (e) => e.message,
              'message',
              contains('Mã Sinh viên đã tồn tại trên hệ thống.'),
            ),
          ),
        );
      },
    );

    test(
      'Tài khoản đã thu hồi (revoked) KHÔNG được tái sử dụng email',
      () async {
        // sv003@example.com thuộc tài khoản SV003 đã thu hồi
        expect(
          () => repository.createStudent(
            identityCode: 'SV88004',
            fullName: 'Tái sinh Email',
            email: 'sv003@example.com',
            phone: '0912345678',
            roomId: 'room-1',
          ),
          throwsA(
            isA<AdminAccountsFailure>().having(
              (e) => e.message,
              'message',
              contains('Email đã tồn tại trên hệ thống.'),
            ),
          ),
        );
      },
    );

    test('Từ chối số điện thoại sai định dạng', () async {
      const invalidPhones = [
        '123456',
        '091234567',
        '091234567890',
        '09abcdef12',
        'abc',
      ];
      for (final phone in invalidPhones) {
        expect(
          () => repository.createStudent(
            identityCode: 'SV88005',
            fullName: 'Sinh Viên Test',
            email: 'testphone@example.com',
            phone: phone,
            roomId: 'room-1',
          ),
          throwsA(
            isA<AdminAccountsFailure>().having(
              (e) => e.message,
              'message',
              contains('Số điện thoại không đúng định dạng.'),
            ),
          ),
        );
      }
    });

    test('Từ chối gắn vào phòng đã ngừng hoạt động (inactive room)', () async {
      // room-4 (C3-210) có isActive: false
      expect(
        () => repository.createStudent(
          identityCode: 'SV88006',
          fullName: 'Sinh Viên Inactive Room',
          email: 'sv.inactive@example.com',
          phone: '0912345678',
          roomId: 'room-4',
        ),
        throwsA(
          isA<AdminAccountsFailure>().having(
            (e) => e.message,
            'message',
            contains('Chỉ được gắn Sinh viên vào phòng đang hoạt động.'),
          ),
        ),
      );
    });

    test('Từ chối gắn vào phòng không tồn tại', () async {
      expect(
        () => repository.createStudent(
          identityCode: 'SV88007',
          fullName: 'Sinh Viên No Room',
          email: 'sv.noroom@example.com',
          phone: '0912345678',
          roomId: 'room-not-found-uuid',
        ),
        throwsA(
          isA<AdminAccountsFailure>().having(
            (e) => e.message,
            'message',
            contains('Phòng không tồn tại.'),
          ),
        ),
      );
    });

    test('getActiveRooms chỉ trả về các phòng có isActive == true', () async {
      final activeRooms = await repository.getActiveRooms();
      expect(activeRooms.isNotEmpty, isTrue);
      expect(activeRooms.every((r) => r.isActive), isTrue);
      expect(activeRooms.any((r) => r.code == 'C3-210'), isFalse);
    });
  });

  group('DF-031: PhoneRules & Email Frontend Validation', () {
    test('PhoneRules validatePhone kiểm tra chính xác số ĐT VN', () {
      expect(PhoneRules.validatePhone(''), isNotNull);
      expect(PhoneRules.validatePhone('091234567'), isNotNull);
      expect(PhoneRules.validatePhone('091234567890'), isNotNull);
      expect(PhoneRules.validatePhone('0912345678'), isNull);
      expect(PhoneRules.validatePhone('+84912345678'), isNull);
    });
  });

  group('DF-031: CreateStudentDialog Widget Tests', () {
    testWidgets('Hiển thị đầy đủ form và thông báo validation khi để trống', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const repository = MockAdminAccountsRepository();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CreateStudentDialog(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra tiêu đề và các trường nhập liệu
      expect(find.text('Tạo tài khoản Sinh viên'), findsOneWidget);
      expect(find.text('Mã Sinh viên *'), findsOneWidget);
      expect(find.text('Họ và tên *'), findsOneWidget);
      expect(find.text('Email liên hệ / đăng nhập *'), findsOneWidget);
      expect(find.text('Số điện thoại *'), findsOneWidget);
      expect(find.text('Gắn phòng KTX *'), findsOneWidget);

      // Bấm nút Tạo tài khoản khi chưa điền thông tin
      await tester.ensureVisible(find.text('Tạo tài khoản'));
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();

      // Các thông báo lỗi validation trên giao diện
      expect(find.text('Vui lòng nhập mã Sinh viên.'), findsOneWidget);
      expect(find.text('Vui lòng nhập họ và tên.'), findsOneWidget);
      expect(find.text('Vui lòng nhập email.'), findsOneWidget);
      expect(find.text('Vui lòng nhập số điện thoại.'), findsOneWidget);
    });

    testWidgets(
      'Điền đầy đủ form hợp lệ, tạo thành công và hiển thị mật khẩu tạm',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const repository = MockAdminAccountsRepository();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: CreateStudentDialog(repository: repository)),
          ),
        );
        await tester.pumpAndSettle();

        // Nhập các trường thông tin
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Mã Sinh viên *'),
          'SV77001',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Họ và tên *'),
          'Đỗ Hoàng Phúc',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Email liên hệ / đăng nhập *'),
          'phuc.dh77@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Số điện thoại *'),
          '0933445566',
        );

        // Phòng đầu tiên (DEMO-A101) đã được chọn mặc định
        // Bấm Tạo tài khoản
        await tester.ensureVisible(find.text('Tạo tài khoản'));
        await tester.tap(find.text('Tạo tài khoản'));
        await tester.pumpAndSettle();

        // Kiểm tra màn hình thành công
        expect(
          find.text('Tạo tài khoản Sinh viên thành công!'),
          findsOneWidget,
        );
        expect(find.text('Đỗ Hoàng Phúc'), findsOneWidget);
        expect(find.text('SV77001'), findsOneWidget);
        expect(find.text('phuc.dh77@example.com'), findsOneWidget);
        expect(find.text('0933445566'), findsOneWidget);
        expect(find.text('Mật khẩu tạm:'), findsOneWidget);
        expect(
          find.text(
            'Sinh viên bắt buộc phải đổi mật khẩu khi đăng nhập lần đầu tiên trước khi có thể sử dụng các chức năng của hệ thống.',
          ),
          findsOneWidget,
        );
        expect(find.text('Hoàn tất và Đóng'), findsOneWidget);
      },
    );
  });

  group('DF-031: AdminAccountsPage Create Button Integration', () {
    testWidgets(
      'Hiển thị nút Tạo tài khoản Sinh viên khi người dùng là Admin',
      (tester) async {
        const repository = MockAdminAccountsRepository();

        await tester.pumpWidget(
          const MaterialApp(
            home: AdminAccountsPage(repository: repository, isAdmin: true),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('create-student-btn')), findsOneWidget);
        expect(find.text('Tạo tài khoản Sinh viên'), findsOneWidget);

        // Bấm nút Tạo tài khoản Sinh viên -> Mở Dialog
        await tester.tap(find.byKey(const Key('create-student-btn')));
        await tester.pumpAndSettle();

        expect(find.byType(CreateStudentDialog), findsOneWidget);
      },
    );

    testWidgets('Không hiển thị nút và chặn màn hình khi không phải Admin', (
      tester,
    ) async {
      const repository = MockAdminAccountsRepository();

      await tester.pumpWidget(
        const MaterialApp(
          home: AdminAccountsPage(repository: repository, isAdmin: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Bạn không có quyền truy cập màn hình này.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('create-student-btn')), findsNothing);
    });
  });

  group('DF-031: First-time Login Forces Password Change', () {
    testWidgets(
      'Sinh viên mới tạo có must_change_password=true bị chuyển sang ChangePasswordPage',
      (tester) async {
        // Hồ sơ Sinh viên mới tạo có mustChangePassword = true, canAccess = false
        final newStudentProfile = UserProfile(
          id: 'new-student-id',
          identityCode: 'SV77001',
          fullName: 'Đỗ Hoàng Phúc',
          email: 'phuc.dh77@example.com',
          phone: '0933445566',
          role: AppRole.student,
          status: 'active',
          room: const RoomProfile(
            id: 'room-1',
            code: 'DEMO-A101',
            building: 'Tòa A',
            isActive: true,
          ),
          mustChangePassword: true,
          canAccess: false,
        );

        final authRepo = _FakeAuthRepository(newStudentProfile);
        final authController = AuthController(repository: authRepo);

        await tester.pumpWidget(
          MaterialApp(home: StartupPage(controller: authController)),
        );
        await tester.pumpAndSettle();

        // Trạng thái yêu cầu đổi mật khẩu
        expect(authController.state, AuthViewState.changePasswordRequired);
        // Giao diện chuyển hướng đến ChangePasswordPage
        expect(find.byType(ChangePasswordPage), findsOneWidget);
        expect(find.text('Đổi mật khẩu tạm'), findsOneWidget);
      },
    );
  });
}
