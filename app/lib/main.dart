import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/dormfix_app.dart';
import 'core/database/local_database.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Bản demo local này chạy trên Android. Hãy chọn Android Emulator hoặc điện thoại Android.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    return;
  }
  try {
    final db = await LocalDatabase.open();
    runApp(DormFixApp(auth: AuthService(AuthRepository(db))));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Không mở được dữ liệu local. Hãy đóng và mở lại ứng dụng; không xóa dữ liệu nếu cần giữ lịch sử.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
