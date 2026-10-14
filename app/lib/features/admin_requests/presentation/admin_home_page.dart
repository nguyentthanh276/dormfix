import 'package:flutter/material.dart';

import '../../../core/models/app_role.dart';
import '../../admin_accounts/presentation/create_student_page.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/role_home_page.dart';

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => _AdminShell(controller: controller);
}

class _AdminShell extends StatelessWidget {
  const _AdminShell({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final profile = controller.profile;
      if (profile == null || profile.role != AppRole.admin) {
        return RoleHomePage(controller: controller, role: AppRole.admin);
      }

      return Scaffold(
        appBar: AppBar(
          title: const Text('DormFix - Quản lý KTX'),
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
                    Icons.admin_panel_settings_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Xin chào quản lý'
                    '${profile.fullName == null ? '' : ', ${profile.fullName}'}',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text('Vai trò: ${AppRole.admin.label}'),
                  const SizedBox(height: 24),

                  // ── Admin actions ──────────────────────────────────
                  _AdminActionCard(
                    icon: Icons.person_add_outlined,
                    title: 'Tạo tài khoản Sinh viên',
                    subtitle: 'Thêm Sinh viên mới và gắn phòng',
                    key: const Key('action-create-student'),
                    onTap: () => pushCreateStudentPage(
                      context,
                      authController: controller,
                    ),
                  ),

                  if (controller.error case final err?) ...[
                    const SizedBox(height: 16),
                    Text(
                      err,
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
}

class _AdminActionCard extends StatelessWidget {
  const _AdminActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
