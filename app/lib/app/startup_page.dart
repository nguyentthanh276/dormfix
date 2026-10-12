import 'package:flutter/material.dart';

/// Temporary startup screen; replace with the authenticated router later.
class StartupPage extends StatelessWidget {
  const StartupPage({super.key, required this.backendReady});

  final bool backendReady;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DormFix')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_repair_service_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'Sửa chữa ký túc xá',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Ứng dụng đang được phát triển.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    backendReady
                        ? 'Đã khởi tạo Supabase. Chức năng đăng nhập sẽ được bổ sung.'
                        : 'Chưa sẵn sàng kết nối dịch vụ. Vui lòng kiểm tra cấu hình.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
