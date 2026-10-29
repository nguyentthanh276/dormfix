import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/dormfix_app.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  String? backendError;

  if (!config.isConfigured) {
    backendError =
        'Thiếu hoặc không hợp lệ cấu hình Supabase. '
        'Hãy kiểm tra SUPABASE_URL và SUPABASE_PUBLISHABLE_KEY trong '
        'config/local.json. Khi chạy Flutter, hãy truyền '
        '--dart-define-from-file=config/local.json rồi khởi động lại.';
  } else {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
    } catch (_) {
      backendError =
          'Không thể khởi tạo dịch vụ Supabase. Vui lòng kiểm tra cấu hình '
          'và kết nối mạng rồi thử lại.';
    }
  }

  runApp(
    DormFixApp(backendReady: backendError == null, backendError: backendError),
  );
}
