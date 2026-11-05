import 'package:dormfix/features/admin_accounts/data/admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/data/mock_admin_accounts_repository.dart';
import 'package:dormfix/features/admin_accounts/presentation/create_technician_dialog.dart';
import 'package:dormfix/core/models/app_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-032: MockAdminAccountsRepository', () {
    test('creates an active technician with temporary password gate', () async {
      const repository = MockAdminAccountsRepository();
      final result = await repository.createTechnician(
        identityCode: 'KTV88001',
        fullName: 'Nguyễn Văn Kỹ',
        email: 'ktv88001@example.com',
        phone: '0912345678',
        temporaryPassword: 'Temp@123',
      );

      expect(result.identityCode, 'KTV88001');
      expect(result.status, 'active');
      expect(result.mustChangePassword, isTrue);
      expect(result.temporaryPassword, 'Temp@123');
      final accounts = await repository.list(
        query: 'KTV88001',
        role: AppRole.technician,
        offset: 0,
        limit: 10,
      );
      expect(accounts, hasLength(1));
    });

    test('does not reuse identity or email from revoked accounts', () async {
      const repository = MockAdminAccountsRepository();

      await expectLater(
        repository.createTechnician(
          identityCode: 'ktv003',
          fullName: 'Kỹ thuật viên khác',
          email: 'fresh-ktv@example.com',
          phone: '0912345678',
        ),
        throwsA(
          isA<AdminAccountsFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Mã Kỹ thuật viên đã tồn tại'),
          ),
        ),
      );

      await expectLater(
        repository.createTechnician(
          identityCode: 'KTV88002',
          fullName: 'Kỹ thuật viên khác',
          email: 'KTV003@EXAMPLE.COM',
          phone: '0912345678',
        ),
        throwsA(
          isA<AdminAccountsFailure>().having(
            (failure) => failure.message,
            'message',
            contains('Email đã tồn tại'),
          ),
        ),
      );
    });

    test('requires a valid phone but allows reuse of a phone number', () async {
      const repository = MockAdminAccountsRepository();
      await expectLater(
        repository.createTechnician(
          identityCode: 'KTV88003',
          fullName: 'Kỹ thuật viên lỗi',
          email: 'ktv88003@example.com',
          phone: '12345',
        ),
        throwsA(isA<AdminAccountsFailure>()),
      );

      final first = await repository.createTechnician(
        identityCode: 'KTV88004',
        fullName: 'Kỹ thuật viên một',
        email: 'ktv88004@example.com',
        phone: '0987654321',
      );
      final second = await repository.createTechnician(
        identityCode: 'KTV88005',
        fullName: 'Kỹ thuật viên hai',
        email: 'ktv88005@example.com',
        phone: '0987654321',
      );
      expect(first.phone, second.phone);
    });
  });

  group('DF-032: CreateTechnicianDialog', () {
    testWidgets('validates required fields and displays temporary password', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const repository = MockAdminAccountsRepository();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CreateTechnicianDialog(repository: repository)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Tạo tài khoản'));
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập mã Kỹ thuật viên.'), findsOneWidget);
      expect(find.text('Vui lòng nhập email.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mã Kỹ thuật viên *'),
        'KTV88006',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên *'),
        'Phan Kỹ Thuật',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email liên hệ / đăng nhập *'),
        'ktv88006@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Số điện thoại *'),
        '+84912345678',
      );
      await tester.ensureVisible(find.text('Tạo tài khoản'));
      await tester.tap(find.text('Tạo tài khoản'));
      await tester.pumpAndSettle();

      expect(
        find.text('Tạo tài khoản Kỹ thuật viên thành công!'),
        findsOneWidget,
      );
      expect(find.text('KTV88006'), findsOneWidget);
      expect(find.text('ktv88006@example.com'), findsOneWidget);
      expect(
        find.text(
          'Kỹ thuật viên phải đổi mật khẩu khi đăng nhập lần đầu trước khi sử dụng hệ thống.',
        ),
        findsOneWidget,
      );
      expect(find.text('Hoàn tất và Đóng'), findsOneWidget);
    });
  });
}
