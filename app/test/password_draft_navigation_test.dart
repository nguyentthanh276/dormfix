import 'package:dormfix/core/theme/app_theme.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/profile/presentation/active_change_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

void main() {
  testWidgets('Back preserves password draft until discard is confirmed', (
    tester,
  ) async {
    final auth = TechnicianTestAuthRepository();
    final controller = AuthController(repository: auth);
    await controller.restoreSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      ActiveChangePasswordPage(controller: controller),
                ),
              ),
              child: const Text('Mở mật khẩu'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở mật khẩu'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('current-password-input')),
      'private-draft',
    );
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục nhập'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('current-password-input')),
          )
          .controller
          ?.text,
      'private-draft',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ thay đổi'));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveChangePasswordPage), findsNothing);
    expect(find.text('Mở mật khẩu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await auth.dispose();
  });
}
