import 'package:dormfix/app/dormfix_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App starts without Supabase credentials on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DormFixApp());
    await tester.pumpAndSettle();
    expect(find.text('DormFix'), findsOneWidget);
    expect(find.text('Chưa sẵn sàng kết nối'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('vi'),
    );
  });
}
