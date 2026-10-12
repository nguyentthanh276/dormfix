import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import 'auth_controller.dart';

class RoleHomePage extends StatelessWidget {
  const RoleHomePage({super.key, required this.controller, required this.role});

  final AuthController controller;
  final AppRole role;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final profile = controller.profile;
      if (profile == null || profile.role != role) {
        return _AccessDeniedPage(controller: controller);
      }

      final (title, greeting) = switch (role) {
        AppRole.admin => ('DormFix - Quản lý KTX', 'Xin chào quản lý'),
        AppRole.student => ('DormFix - Sinh viên', 'Xin chào sinh viên'),
        AppRole.technician => (
          'DormFix - Kỹ thuật viên',
          'Xin chào kỹ thuật viên',
        ),
      };
      final name = profile.fullName;

      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            TextButton.icon(
              onPressed: controller.isLoading ? null : controller.signOut,
              icon: controller.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _roleIcon(role),
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$greeting${name == null ? '' : ', $name'}',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text('Vai trò: ${role.label}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Khu vực nghiệp vụ đang được phát triển.',
                    textAlign: TextAlign.center,
                  ),
                  if (controller.error case final error?) ...[
                    const SizedBox(height: 16),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  IconData _roleIcon(AppRole role) => switch (role) {
    AppRole.admin => Icons.admin_panel_settings_outlined,
    AppRole.student => Icons.school_outlined,
    AppRole.technician => Icons.handyman_outlined,
  };
}

class _AccessDeniedPage extends StatelessWidget {
  const _AccessDeniedPage({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DormFix')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Không thể xác minh quyền truy cập. Vui lòng đăng nhập lại.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: controller.isLoading ? null : controller.signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
      ),
    ),
  );
}
