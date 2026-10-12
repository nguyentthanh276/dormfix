import 'package:dormfix/app/dormfix_app.dart';
import 'package:dormfix/core/database/local_database.dart';
import 'package:dormfix/features/auth/data/auth_repository.dart';
import 'package:dormfix/features/auth/data/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('Login screen fits a small Android display and validates form', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => LocalDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;
    final auth = AuthService(AuthRepository(db));
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(auth.dispose);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(DormFixApp(auth: auth));
    await tester.pumpAndSettle();
    expect(find.text('DormFix'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email đúng định dạng.'), findsOneWidget);
    expect(find.text('Nhập mật khẩu.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () => auth.login('student@example.com', 'Dormfix393'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Bạn cần đổi mật khẩu tạm trước khi sử dụng.'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Lưu mật khẩu'), findsOneWidget);
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.text('DormFix'), findsOneWidget);
    expect(auth.current, isNull);
    expect(tester.takeException(), isNull);
  });
}
